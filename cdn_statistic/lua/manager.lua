
--[[******************************************************
File name : manager.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-03-10 17:53
Modified Date : 2015-03-10 17:53
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
******************************************************--]]
 
module("manager", package.seeall);

--用户详情redis key
function get_user_info_key(uuid)
	return "online_user:info:" .. uuid ;
end

--在线用户心跳redis key
function get_heartbeat_key(oldVer)
	if true == oldVer then
		return "old_heartbeat:uuid";
	else
		return "heartbeat:uuid";
	end
end

--在线用户redis queue
local function get_user_info_queue_key(oldVer)
	local prefix = "";
	if oldVer then
		prefix = "old_";
	end
	return prefix .. "online_user:queue";
end

--点播详单redis queue
local function get_click_detail_queue_key(oldVer)
	local prefix = "";
	if oldVer then
		prefix = "old_";
	end
	return prefix .. "click_detail:queue";
end

--ES在线用户数据库名A
function get_online_user_dbname()
	local db_name = es_db_prefix .. "online";
	return db_name;
end

--ES点播详单数据库名
function get_click_detail_dbname(date)
	if date then
		return es_db_prefix .. "detail_" .. date;
	end

	local db_name = es_db_prefix .. "detail_" .. os.date("%Y-%m-%d", os.time()-3600*8);
	return db_name;
end

--ES在线用户表名
function get_user_info_tlb_name(oldVer)
	local prefix = "";
	if oldVer then
		prefix = "old_";
	end
	return prefix .. "online_user";
end

--redis点播详单表名
function get_click_detail_tlb_name(oldVer)
	local prefix = "";
	if oldVer then
		prefix = "old_";
	end
	return prefix .. "click_detail";
end

--在线用户入列
function add_user_info(redis, oldVer, body)
	local score = os.time();
	local queue_key = get_user_info_queue_key(oldVer);

	local uuid = body["uuid"];
	local info_key = get_user_info_key(uuid);

	redis:init_pipeline();
	redis:zadd(queue_key, score, uuid);
	redis:hmset(info_key, body);
	redis:expire(info_key, rdb_max_expire); --用户信息最大暂存时间（1天）
	local res, err = redis:commit_pipeline();
	if err then
		ngx.log(ngx.ERR, "[REDIS] zadd queue: ", queue_key, 
				", body: ", cjson.encode(body), 
				", err: ", err);
	end

	return err;
end

local function get_user_info_by_uuid(redis, uuid)
	local key = get_user_info_key(uuid);
	local res, err = redis:hgetall(key);
	if err then
		ngx.log(ngx.ERR, "[REDIS] get user info failed , uuid:",uuid, ", err:", err);
		return nil;
	end

	local row = {};
	for i,v in ipairs(res) do
		if i%2 == 1 then
			row[v] = res[i+1];
		end
	end

	return row;
end

--在线用户出列
function get_user_info(redis, oldVer)
	--所有在线用户UUID
	local key = get_user_info_queue_key(oldVer);
	local res, err = redis:zrange(key, 0, const_max_uuid);
	if err then
		ngx.log(ngx.ERR, "[REDIS] err: ", err, 
				"res: ", cjson.encode(res));
		return nil, nil;
	end

	local data = {};
	for i, uuid in ipairs(res) do
		local usrInfo = get_user_info_by_uuid(redis, uuid);		
		table.insert(data, usrInfo);
	end
		
	return res, data;
end

--在线用户从队列删除
function del_from_online_user_queue(redis, oldVer, body)
	local key = get_user_info_queue_key(oldVer);

	redis:init_pipeline();
	for i, uuid in ipairs(body) do
		redis:zrem(key, uuid);
	end
	local res, err = redis:commit_pipeline();

	if err then
		ngx.log(ngx.ERR, "[REDIS] del queue:", key, 
				", body: ", cjson.encode(body), 
				", err: ", err);
	end
	
	return err;
end


--点播详单入列
function add_click_detail_to_queue(redis, oldVer, body)
	local score = os.time();
	local key = get_click_detail_queue_key(oldVer);
	local uuid = body["uuid"];

	redis:init_pipeline();
	redis:zadd(key, score, uuid);
	local res, err = redis:commit_pipeline();

	if err then
		ngx.log(ngx.ERR, "[REDIS] zadd queue:", key, 
				", body: ", cjson.encode(body), 
				", err: ", err);
	end

	return err;
end

function add_click_detail_to_queues(redis, oldVer, bodies)
	local score = os.time();
	local key = get_click_detail_queue_key(oldVer);

	redis:init_pipeline();
	for i, uuid in ipairs(bodies) do
		redis:zadd(key, score, uuid);
	end
	local res, err = redis:commit_pipeline();

	if err then
		ngx.log(ngx.ERR, "[REDIS] zadd queue: ", key, 
				", body: ", cjson.encode(bodies), 
				", err: ", err);
	end

	return err;
end


--点播详单出列
function get_click_detail_from_queue(redis, oldVer)
	local queue_key = get_click_detail_queue_key(oldVer);
	local res, err = redis:zrange(queue_key, 0, const_max_uuid);
	if err then
		ngx.log(ngx.ERR, "[REIDS] err: ", err, 
				"res: ", cjson.encode(res));
		return nil, nil;
	end

	local data = {};
	for i, uuid in ipairs(res) do
		local usrInfo = get_user_info_by_uuid(redis, uuid);		
		table.insert(data, usrInfo);
	end
		
	return res, data
end

--点播详单从队列删除
function del_click_detail(redis, oldVer, body)
	local click_detail_key = get_click_detail_queue_key(oldVer);
	local online_user_key = get_user_info_queue_key(oldVer);
	local heartbeat_key = get_heartbeat_key(oldVer);
	redis:init_pipeline();

	for i, uuid in ipairs(body) do
		--点击详单队列
		redis:zrem(click_detail_key, uuid);
		--在线用户队列
		redis:zrem(online_user_key, uuid);
		--心跳zset
		redis:zrem(heartbeat_key, uuid);
		--
		--任务详情
		local userinfo_key = get_user_info_key(uuid);
		redis:hdel(userinfo_key, uuid);
	end
	local res, err = redis:commit_pipeline();

	if err then
		ngx.log(ngx.ERR, "[REDIS] del queue: ", key, 
					", body: ", cjson.encode(body), 
					", err: ", err);
	end
	
	return err;
end

----------------------------------------
----------------------------------------
--批量上线
function online_bulk_from_queue(redis, oldVer)
	assert(redis);

	--1. 获取所有队列的UUID
	local res, bodies = mgr.get_user_info(redis, oldVer);		
	if not res or nil == next(res) then
		--1.1. 清空队列
		local ret = mgr.del_from_online_user_queue(redis, oldVer, res);

		--1.2. 计数器
		g_data_stat_dict:incr("ONLINE_CNT", #res);

		return ngx.HTTP_GONE;
	end

	--2. 批量发送至ES	
	local db_name = mgr.get_online_user_dbname();
	local tlb_name = mgr.get_user_info_tlb_name(oldVer);
	local code = util.send_bulk(bodies, db_name, tlb_name, "index");
	if code ~= ngx.HTTP_OK then
		return code;
	end

	--3. 清空队列
	local ret = mgr.del_from_online_user_queue(redis, oldVer, res);

	--4. 计数器
	g_data_stat_dict:incr("ONLINE_CNT", #res);

	return ngx.HTTP_OK;
end

--
--批量下线
function offline_bulk_from_queue(redis, oldVer)

	--1. 获取所有等待的UUID
	local res, bodies = mgr.get_click_detail_from_queue(redis, oldVer);		
	--redis有可能丢失信息，所以取到数据才入详单
	if nil == res or next(res) == nil then
		--1.1. 出在线用户表
		local db_name = mgr.get_online_user_dbname();
		local tlb_name = mgr.get_user_info_tlb_name(oldVer);
		local code = util.send_bulk(bodies, db_name, tlb_name, "delete");
		if code ~= ngx.HTTP_OK then
			return code;
		end

		--1.2. 清空队列
		local ret = mgr.del_click_detail(redis, oldVer, res);

		--1.3. 计数器
		g_data_stat_dict:incr("OFFLINE_CNT", #res);

		return ngx.HTTP_OK;
	end

	--2. 入ES点播详单表
	local db_name = mgr.get_click_detail_dbname(nil);
	local tlb_name = mgr.get_click_detail_tlb_name(oldVer);
	local code = util.send_bulk(bodies, db_name, tlb_name, "index");
	if code ~= ngx.HTTP_OK then
		return code;
	end

	--3. 出在线用户表
	db_name = mgr.get_online_user_dbname();
	tlb_name = mgr.get_user_info_tlb_name(oldVer);
	local code = util.send_bulk(bodies, db_name, tlb_name, "delete");
	if code ~= ngx.HTTP_OK then
		return code;
	end

	--4. 清空队列
	local ret = mgr.del_click_detail(redis, oldVer, res);

	--5. 计数器
	g_data_stat_dict:incr("OFFLINE_CNT", #res);

	return ngx.HTTP_OK;
end

function get_uuid_count(redis)
	local data = {}

	local old_heartbeat_key = get_heartbeat_key(true);	
	local heartbeat_key = get_heartbeat_key(false);	
	local old_user_info_queue_key = get_user_info_queue_key(true);
	local user_info_queue_key = get_user_info_queue_key(false);
	local old_detail_queue_key = get_click_detail_queue_key(true);
	local detail_queue_key = get_click_detail_queue_key(false);

	redis:init_pipeline();
	redis:zcard(old_heartbeat_key);		
	redis:zcard(heartbeat_key);		
	redis:zcard(old_user_info_queue_key);		
	redis:zcard(user_info_queue_key);		
	redis:zcard(old_detail_queue_key);		
	redis:zcard(detail_queue_key);		
	local res, err = redis:commit_pipeline();
	if err then
		ngx.log(ngx.ERR, "[REDIS] get count err: ", err);
		return data;
	end

	return res;
end

