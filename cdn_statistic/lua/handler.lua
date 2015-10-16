
--[[******************************************************
File name : handler.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-03-16 14:17
Modified Date : 2015-03-16 14:17
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
******************************************************--]]
 
module("handler", package.seeall)

local on_timer = nil;
--写ES表必须的字段
local function get_scheme()
	local scheme = {"nid",
		"fid", 
		"srgid", 
		"urgid", 
		"host", 
		"driverId", 
		"uri", 
		"t", 
		"pno", 
		"arange",
		"rdur",
		"limitrate",
		"ruip",
		"uuid"
	};
	return scheme;
end

--老版本调度返回的播放串写ES必须的字段
local function get_old_scheme()
	local scheme = {
		"host", 
		"uri", 
		"t", 
		"ruip",
		"uuid"
	};
	return scheme;
end

local function str_split(s, p)
	local rt= {}
	string.gsub(s, '[^'..p..']+', function(w) table.insert(rt, w) end )
	return rt
end

local function split_to_map(str, p)
	local tlb = str_split(str, p);
	local mp = {};
	for i, v in ipairs(tlb) do
		if 1 == math.fmod(i, 2) then
			mp[v] = tlb[i+1];

			ngx.log(ngx.NOTICE, "payload, k:", v, ",v:",mp[v]);
		end
	end

	return mp;
end

local function parse_url(url)
	local info = resty_url.parse(url);
	if not info or not info["query"] then
		return nil;
	end

	info["params"] = ngx.decode_args(info["query"]);

	for k, v in pairs(info["params"]) do
		if "payload" == k then
			v = string.gsub(v, "usertoken=", "");
			local payload = str_split(v, "|");

			for i, elm in ipairs(payload) do
				local vv = str_split(elm, "^");
				for ii, token in ipairs(vv) do
					local mp = split_to_map(token, "=");
					for tk, tv in pairs(mp) do
						info["params"][tk] = tv;					
					end
				end
			end
		end
	end

	return info;
	--[[
	--host
	--path
	--query
	--scheme
	--port
	--authority
	--]]
end

local function nil_check(var, defaultVal)
	return var or defaultVal;
end

local function need_health_check()
	--上次建康检查时间
	local last_check_time = g_data_stat_dict:get(STR_HEALTH_CHECK);
	if 0 == last_check_time then
		--更新检查时间
		g_data_stat_dict:set(STR_HEALTH_CHECK, os.time());
		return true;
	end

	--未到检查时间
	if os.time() - last_check_time < 1 then
		return false;
	end

	--更新检查时间
	g_data_stat_dict:set(STR_HEALTH_CHECK, os.time());
	return true;
end

local function is_timer_on()
	local timer_on = g_data_stat_dict:get(STR_TIMER_ON);

	--上一个定时器还未执行
	if 1 == timer_on then
		return true;
	end

	return false;
end

local function reset_timer_stat()
	g_data_stat_dict:set(STR_TIMER_ON, 0);
end

local function set_timer_stat()
	g_data_stat_dict:set(STR_TIMER_ON, 1);
end

local function parse_body(url)
	ngx.log(ngx.NOTICE, "new play url: ", url);

	--解析url http://host/uri?param
	local info = parse_url(url);
	if not info then
		ngx.log(ngx.NOTICE, "wrong format url: ", url);
		return nil, nil;
	end

	if 0 ~= tonumber(util.get_ip_type(info["host"])) then
		ngx.log(ngx.NOTICE, "wrong format host: ", info["host"]);
		return nil, nil; 
	end 

	--校验必须的字段
	local body = {};			
	local scheme = get_scheme();
	for i, field in ipairs(scheme) do
		body[field] = info["params"][field];
	end

	--assert(body["uuid"]);
	if body["ruip"] == nil then
		local headers  = ngx.req.get_headers();
		body["ruip"] = headers["X-Forwarded-For"];
	end

	body["ruip"] = nil_check(body["ruip"], ngx.var.remote_addr);
	body["t"] = nil_check(util.hex_to_string(body["t"]), os.time());
	body["host"] = info["host"];
	body["connTime"] = os.date("%Y-%m-%dT%H:%M:%S.000",os.time());
	body["connTime"] = body["connTime"] .. "+" .. time_zone;

	local oldVer = (body["urgid"] == nil);
	if true == oldVer then
		body["uri"] = util.get_uri(info["path"]);
	else
		body["uri"] = info["path"];
	end

	--ngx.log(ngx.NOTICE, "body: ", cjson.encode(body));
	
	return oldVer, body;
end

local function DJBhash(uuid, num)
	--local hash = ngx.crc32_long(uuid);
	--local hash = ngx.crc32_short(uuid);
	local hash = mmh3.hash32(uuid, 0);
	return  1+math.fmod(hash, num);
end

--一致性hash选择主机
local function get_rdbhost(uuid)
	return rdb_host;
end

--一致性hash选择端口
function get_port(uuid)
	return rdb_port;
end

local function __on_heartbeat(redis, oldVer, body)
	--1. 获取redis key
	local heartbeat_key = mgr.get_heartbeat_key(oldVer);
	local score = os.time();
	local uuid = body["uuid"];

	--2. 更新时间
	redis:init_pipeline();
	redis:zadd(heartbeat_key, score, uuid);
	redis:expire(heartbeat_key, rdb_min_expire); --心跳会不断更新过期时间，设置为最小即可
	local res, err = redis:commit_pipeline();

	if err then
		ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] zadd heartbeat_key: ", heartbeat_key, ", uuid: ", uuid);
		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	return ngx.HTTP_OK;
end

local function is_exists(redis, oldVer, uuid)
	local info_key = mgr.get_user_info_key(uuid);
	local res, err = redis:hexists(info_key, "uuid");
	if err then
		ngx.log(ngx.WARN, "[REDIS] hexist: ",uuid, ", err:", err);
		return false;
	end

	if res and res == 0 then
		return false;
	end

	return true;
end


--创建在线用户表
function create_online_table(args)
	local tlb_fmt = [[
	{
		"template": "titan_*",
			"settings": {
				"index.number_of_shards": 5,
				"number_of_replicas": 1
			},
			"mappings": {
				"old_online_user": {
					"properties": {
						"host": {
							"type": "string",
							"index": "not_analyzed"
						},
						"uri": {
							"type": "string",
							"index": "not_analyzed"
						},
						"ruip": {
							"type": "string",
							"index": "not_analyzed"
						},
						"zone": {
							"type": "string",
							"index": "not_analyzed"
						},
						"isp": {
							"type": "string",
							"index": "not_analyzed"
						},
						"country": {
							"type": "string",
							"index": "not_analyzed"
						},
						"province": {
							"type": "string",
							"index": "not_analyzed"
						},
						"city": {
							"type": "string",
							"index": "not_analyzed"
						},
						"longitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"latitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"t": {
							"type": "integer",
							"index": "not_analyzed"
						},
						"connTime": {
							"type": "date",
							"format": "dateOptionalTime"
						},
						"uuid": {
							"type": "string",
							"index": "not_analyzed"
						}
					}
				},
				"online_user": {
					"properties": {
						"nid": {
							"type": "integer",
							"index": "analyzed"
						},
						"fid": {
							"type": "string",
							"index": "not_analyzed"
						},
						"srgid": {
							"type": "integer",
							"index": "analyzed"
						},
						"urgid": {
							"type": "integer",
							"index": "analyzed"
						},
						"host": {
							"type": "string",
							"index": "not_analyzed"
						},
						"driverId": {
							"type": "string",
							"index": "not_analyzed"
						},
						"uri": {
							"type": "string",
							"index": "not_analyzed"
						},
						"ruip": {
							"type": "string",
							"index": "not_analyzed"
						},
						"pno": {
							"type": "string",
							"index": "not_analyzed"
						},
						"zone": {
							"type": "string",
							"index": "not_analyzed"
						},
						"isp": {
							"type": "string",
							"index": "not_analyzed"
						},
						"country": {
							"type": "string",
							"index": "not_analyzed"
						},
						"province": {
							"type": "string",
							"index": "not_analyzed"
						},
						"city": {
							"type": "string",
							"index": "not_analyzed"
						},
						"longitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"latitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"t": {
							"type": "integer",
							"index": "not_analyzed"
						},
						"connTime": {
							"type": "date",
							"format": "dateOptionalTime"
						},
						"uuid": {
							"type": "string",
							"index": "not_analyzed"
						}
					}
				},
				"old_click_detail": {
					"properties": {
						"host": {
							"type": "string",
							"index": "not_analyzed"
						},
						"uri": {
							"type": "string",
							"index": "not_analyzed"
						},
						"ruip": {
							"type": "string",
							"index": "not_analyzed"
						},
						"zone": {
							"type": "string",
							"index": "not_analyzed"
						},
						"isp": {
							"type": "string",
							"index": "not_analyzed"
						},
						"country": {
							"type": "string",
							"index": "not_analyzed"
						},
						"province": {
							"type": "string",
							"index": "not_analyzed"
						},
						"city": {
							"type": "string",
							"index": "not_analyzed"
						},
						"longitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"latitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"t": {
							"type": "integer",
							"index": "not_analyzed"
						},
						"connTime": {
							"type": "date",
							"format": "dateOptionalTime"
						},
						"uuid": {
							"type": "string",
							"index": "not_analyzed"
						},
						"disconnTime": {
							"type": "date",
							"format": "dateOptionalTime"
						},
						"timeOut": {
							"type": "integer",
							"index": "not_analyzed"
						}
					}
				},
				"click_detail": {
					"properties": {
						"nid": {
							"type": "integer",
							"index": "analyzed"
						},
						"fid": {
							"type": "string",
							"index": "not_analyzed"
						},
						"srgid": {
							"type": "integer",
							"index": "analyzed"
						},
						"urgid": {
							"type": "integer",
							"index": "not_analyzed"
						},
						"host": {
							"type": "string",
							"index": "not_analyzed"
						},
						"driverId": {
							"type": "string",
							"index": "not_analyzed"
						},
						"uri": {
							"type": "string",
							"index": "not_analyzed"
						},
						"ruip": {
							"type": "string",
							"index": "not_analyzed"
						},
						"zone": {
							"type": "string",
							"index": "not_analyzed"
						},
						"isp": {
							"type": "string",
							"index": "not_analyzed"
						},
						"country": {
							"type": "string",
							"index": "not_analyzed"
						},
						"province": {
							"type": "string",
							"index": "not_analyzed"
						},
						"city": {
							"type": "string",
							"index": "not_analyzed"
						},
						"longitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"latitude": {
							"type": "string",
							"index": "not_analyzed"
						},
						"t": {
							"type": "integer",
							"index": "not_analyzed"
						},
						"connTime": {
							"type": "date",
							"format": "dateOptionalTime"
						},
						"uuid": {
							"type": "string",
							"index": "not_analyzed"
						},
						"disconnTime": {
							"type": "date",
							"format": "dateOptionalTime"
						},
						"timeOut": {
							"type": "integer",
							"index": "not_analyzed"
						}
					}
				}
			}
	}
	]];
	local data = cjson.decode(tlb_fmt);
	local url = es_host .. "/_template/titan";
	local code, body = util.post(url, cjson.encode(data));		
	if ngx.HTTP_OK ~= code then
		ngx.log(ngx.ERR, "[FATAL] create_table failed!");
	end

	return code;
end

--创建点播详单表，每天一张表
function create_table(args)
	return create_online_table(args);
end

local function __health_check(redis, oldVer)
	--1. 获取KEY
	local key = mgr.get_heartbeat_key(oldVer);
	local timeline = os.time() - health_check_timeout;
	assert(redis);

	--2. 检查超时用UUID
	local res, err = redis:zrangebyscore(key, 0, timeline, 'LIMIT', 0, const_max_uuid);
	if err then
		ngx.log(ngx.ERR, "[REDIS] err: ", err, "res: ", cjson.encode(res));
		return;
	end
	
	if not res or next(res) == nil then
		return;
	end
	
	--3. 超时UUID详情入点播详单队列
	err = mgr.add_click_detail_to_queues(redis, oldVer, res);

	--4. 临时字典记录超时UUID，方便统计
	for i, uuid in ipairs(res) do
		g_expire_uuid_dict:add(uuid, "1");
	end
end

--启动定时器
local function start_timer()
	--上一个定时器还未执行
	if true == is_timer_on() then
		ngx.log(ngx.NOTICE, "failed to create timer: timer on");
		return;
	end

	--启动定时器
	local ok, err = ngx.timer.at(bulk_interval, on_timer);
	if not ok then
		ngx.log(ngx.ERR, "failed to create timer: ", err);
		return;
	end

	set_timer_stat();
end

on_timer = function()

	--ngx.log(ngx.NOTICE, "=============--on---timer--==================");
	--1. 超时的UUID放入点播详单队列
	if true == need_health_check() then
		--1. 获取redis 连接
		local redis = rdb.get_connection(host, port);
		if not redis then
			ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: "
					, host, ", port: ", port);

			reset_timer_stat();
			start_timer();
			return;
		end

		--2. 旧版本
		__health_check(redis, true);

		--3. 新版本
		__health_check(redis, false);

		rdb.keepalive(redis);
	end


	--1. 获取redis 连接
	local redis = rdb.get_connection(rdb_host, rdb_port);
	if not redis then
		ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ", rdb_host, ", port: ", rdb_port);

		reset_timer_stat();
		start_timer();
		return;
	end

	--2. 旧版本
	mgr.online_bulk_from_queue(redis, true);
	mgr.online_bulk_from_queue(redis, false);

	--3. 新版本
	mgr.offline_bulk_from_queue(redis, true);
	mgr.offline_bulk_from_queue(redis, false);

	--4. 连接放入连接池
	rdb.keepalive(redis);

	--启动定时器
	reset_timer_stat();
	start_timer();
end


--处理心跳
function on_heartbeat(args)
	if 1 then return ngx.HTTP_OK;end
	--1. 参数检查
	if not args["url"] then
		return ngx.HTTP_BAD_REQUEST;
	end

	local url = ngx.unescape_uri(args["url"]);
	local oldVer, body = parse_body(url);
	if not body or not body["uuid"] then
		--ngx.log(ngx.ERR, "[MAIN] uuid not found, url: ", url);
		return ngx.HTTP_BAD_REQUEST;
	end

	--2. 获取redis连接
	local uuid = body["uuid"];
	local rdbport = get_port(uuid);
	local rdbhost = get_rdbhost(uuid);
	local redis = rdb.get_connection(rdbhost, rdbport);
	if not redis then
		ngx.log(ngx.ERR, "[ONLINE HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ", rdbhost, ", port: ", rdbport);
		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	rdb.keepalive(redis);

	--3. 检查该用户有没有发过上线心跳
	redis = rdb.get_connection(rdbhost, rdbport);
	if not redis then
		ngx.log(ngx.ERR, "[ONLINE HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ", 
				rdbhost, ", port: ", rdbport);
		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	if false == is_exists(redis, oldVer, body["uuid"]) then
		ngx.log(ngx.NOTICE, "NOT EXIST, uuid: ", body["uuid"]);
		--[[
		--自动切为上线模式
		--3.1 先入心跳
		local code = __on_heartbeat(redis, oldVer, body);
		if code ~= ngx.HTTP_OK then
			rdb.keepalive(redis);
			return code;
		end

		--3.2. 入等待队列
		local err = mgr.add_user_info(redis, oldVer, body);
		if err then
			rdb.keepalive(redis);
			ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] add user info err: ", err);

			return ngx.HTTP_INTERNAL_SERVER_ERROR;
		end
		rdb.keepalive(redis);

		--3.2. 处理完成，返回
		return code;
		--]]
		return ngx.HTTP_GONE;
	end

	--4. 入心跳
	local code = __on_heartbeat(redis, oldVer, body);
	rdb.keepalive(redis);

	return code;
end


--处理上线（开始播放）
function on_online(args)
	--if 1 then return ngx.HTTP_OK;end
	--1. 参数检查
	local url = ngx.unescape_uri(args["url"]);
	local oldVer, body = parse_body(url);
	if not body or not body["uuid"] then
		--ngx.log(ngx.ERR, "[MAIN] uuid not found, url: ", url);
		return ngx.HTTP_BAD_REQUEST;
	end

	--2. 获取redis连接
	local uuid = body["uuid"];
	local rdbport = get_port(uuid);
	local rdbhost = get_rdbhost(uuid);
	local redis = rdb.get_connection(rdbhost, rdbport);
	if not redis then
		ngx.log(ngx.ERR, "[ONLINE HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ", 
				rdbhost, ", port: ", rdbport);
		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	--防止程序启动时大量并发连接，先入连接池
	rdb.keepalive(redis);

	--3. 先入心跳
	redis = rdb.get_connection(rdbhost, rdbport);
	if not redis then
		ngx.log(ngx.ERR, "[ONLINE HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ", 
				rdbhost, ", port: ", rdbport);
		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	local code = __on_heartbeat(redis, oldVer, body);
	if code ~= ngx.HTTP_OK then
		rdb.keepalive(redis);
		return code;
	end

	--4. 入等待队列
	local err = mgr.add_user_info(redis, oldVer, body);
	if err then
		rdb.keepalive(redis);
		ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] add user info err: ", err);

		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	rdb.keepalive(redis);

	return ngx.HTTP_OK;
end

local function __on_offline(oldVer, body, port)
	
	local uuid = body["uuid"];
	if nil == port then
		rdbport = get_port(uuid);
	else
		rdbport = port;
	end
	ngx.log(ngx.NOTICE, "offline: ", cjson.encode(body));

	--入点播详单队列
	local rdbhost = get_rdbhost(uuid);
	local redis = rdb.get_connection(rdbhost, rdbport);
	if not redis then
		ngx.log(ngx.ERR, "[OFF LINE HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ",
				rdbhost, ", port: ",rdbport);
		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	--防止程序启动时大量并发连接，先入连接池
	rdb.keepalive(redis);

	redis = rdb.get_connection(rdbhost, rdbport);
	if not redis then
		ngx.log(ngx.ERR, "[ONLINE HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ", 
				rdbhost, ", port: ", rdbport);
		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end

	local err = mgr.add_click_detail_to_queue(redis, oldVer, body);
	if err then
		rdb.keepalive(redis);
		ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] add click detail to queue err: ", err);

		return ngx.HTTP_INTERNAL_SERVER_ERROR;
	end
	rdb.keepalive(redis);
	return ngx.HTTP_OK;
end


--处理下线（停止播放）
function on_offline(args)
	if 1 then return ngx.HTTP_OK;end

	local url = ngx.unescape_uri(args["url"]);
	local oldVer, body = parse_body(url);
	if not body or not body["uuid"] then
		--ngx.log(ngx.ERR, "[MAIN] uuid not found, url: ", url);
		return ngx.HTTP_BAD_REQUEST;
	end

	return __on_offline(oldVer, body, nil);
end

--处理超时用户
function on_health_check()
	start_timer();

	--1. 检查是否需要health_check
	if false == need_health_check() then
		return ngx.HTTP_OK;
	end

	--2. 超时的UUID放入点播详单队列
	--1. 获取redis 连接
	local redis = rdb.get_connection(rdb_host, rdb_port);
	if not redis then
		ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: ", rdb_host, ", port: ", rdb_port);
		return ngx.HTTP_GONE;
	end

	--2. 旧版本
	__health_check(redis, true);

	--3. 新版本
	__health_check(redis, false);

	--4. 连接入池
	rdb.keepalive(redis);

	return ngx.HTTP_OK;
end

local function get_uuid_in_port(host, port)
	local res = {};

	local redis = rdb.get_connection(host, port);
	if not redis then
		ngx.log(ngx.ERR, "[HEART BEAT] err: redis connect failed, host: "
				, host, ", port: ", port);
		return res;
	end

	local data = mgr.get_uuid_count(redis) or {};
	res["host"] = host;
	res["port"] = port;
	res["data"] = data; 
	rdb.keepalive(redis);

	return res;
end

function get_uuid_count()
	local cnt = 0;

	local data = {};
	local sub_data = get_uuid_in_port(rdb_host, rdb_port);	
	table.insert(data, sub_data);

	return data;
end

local function __reset(host, port)
	local redis = rdb.get_connection(host, port);
	if not redis then
		ngx.log(ngx.ERR, "[HEART BEAT] err: redis connect failed, host: ", host, ", port: ", port);
	end
	
	--clear
	local res, err = redis:flushall();
	if err then
		ngx.log(ngx.ERR, "redis flush all err: ", err);
	end

	rdb.keepalive(redis);
	
end

function clear_all()

	__reset(rdb_host, rdb_port);

	--清空ES
	--local url = es_host .. "/*";
	--util.http_send(url, "DELETE");

	return ngx.HTTP_OK;
end

function __timeout_force_offline(oldVer)
	local t = os.time()-3600*uuid_alive_hour;
	local time_thresh = os.date("%Y-%m-%dT%H:%M:%S.000", t) .. "+" .. time_zone;

	--1. 在线用户表中查询超时的UUID
	local query_string =[[
		{"query":{"bool":{"must":[{"range":{"connTime":{"lt":"]] .. tostring(time_thresh) .. [["}}}]}}}
	]];

	query_string = cjson.decode(query_string);
	query_string = cjson.encode(query_string);

	local tlb_name = "online_user";
	if true == oldVer then
		tlb_name = "old_online_user";
	end
	local db_name = "titan_online";

	local ext = "/_search?search_type=query_then_fetch&size=" .. tostring(const_max_uuid);
	local url = es_host .. "/titan_online" .. "/" .. tlb_name .. ext ;
	local code, res_json = util.post(url, query_string);
	if res_json == nil then
		return ;
	end
	ngx.log(ngx.NOTICE, "query data: ", res_json);

	local res = cjson.decode(res_json);
	uuid_array = res["hits"];
	if uuid_array["total"] <=0 then
		return;
	end

	uuid_array = uuid_array["hits"];
	local bodies = {};
	local uuids = {};
	for i, body in ipairs(uuid_array) do
		table.insert(bodies, body["_source"]);	
		table.insert(uuids, body["_id"]);
	end

	--2. 入ES点播详单表
	--
	util.send_bulk(bodies, db_name, tlb_name, "index");	
		
	--
	--3. 从ES在线用户表删除
	--
	util.send_bulk(bodies, db_name, tlb_name, "delete");	
	--
	
	--4. 清理REDIS heartbeat online_queue detail_queue user_info	
	local redis = rdb.get_connection(rdb_host, rdb_port);
	mgr.del_click_detail(redis, oldVer, uuids);  
end

function timeout_force_offline()
	__timeout_force_offline(true);

	__timeout_force_offline(false);
end

