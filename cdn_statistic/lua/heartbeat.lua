
--[[******************************************************
File name : heartbeat.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-02-10 10:07
Modified Date : 2015-02-10 10:07
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
******************************************************--]]
 
module("heartbeat", package.seeall);

function get_uuid_count()
	local data = handler.get_uuid_count();
	ngx.say(cjson.encode(data));
end

function on_heartbeat()
	local get_args  = ngx.req.get_uri_args();
	if not get_args then
		ngx.exit(ngx.HTTP_FORBBIDEN);
	end

	local status = handler.on_heartbeat(get_args);	
	ngx.exit(status);
end

function on_start_play()
	local post_args = ngx.req.get_post_args();
	local get_args  = ngx.req.get_uri_args();
	if not get_args then
		ngx.exit(ngx.HTTP_FORBBIDEN);
	end

	--处理用户上线	
	ngx.log(ngx.NOTICE, "[SESSION] data: ", cjson.encode(post_args));
	local code = handler.on_online(get_args);	

	ngx.exit(code);
end

function on_end_play()
	local get_args  = ngx.req.get_uri_args();
	if not get_args then
		ngx.exit(ngx.HTTP_FORBBIDEN);
	end

	ngx.log(ngx.NOTICE, "[SESSION] data: ", cjson.encode(get_args));
	--处理用户下线	
	local code = handler.on_offline(get_args);
	ngx.exit(code);		
end

function on_create_table()
	local get_args  = ngx.req.get_uri_args();

	local code = handler.create_table(get_args);
	ngx.exit(code);
end

function on_create_online_table()
	local get_args  = ngx.req.get_uri_args();

	local code = handler.create_online_table(get_args);
	ngx.exit(code);
end


function on_health_check()
	local code = handler.on_health_check();
	ngx.exit(code);
end

local function get_hostname()
	local hostnameio = io.popen("hostname")
	local hostname = hostnameio:read()
	hostnameio:close()
	return hostname;
end

--注册系统服务
function regist()
	if 0 == enable_regist then
		return ngx.exit(ngx.HTTP_OK);
	end

	local serverUrl = regist_url; 
	local post_body = {};
	post_body["EpochTime"] = string.format("%x", os.time()); 
	post_body["NodeName"] = get_hostname();
	post_body["Version"] = version;

	des3_key = g_data_param_dict:get("des3_key");
	des3_iv = g_data_param_dict:get("des3_iv");

	local data = cjson.encode(post_body);
	ngx.log(ngx.NOTICE, "[REG], url: ", serverUrl, ", post: ", data);

	local ret, data = des3.encode(data, des3_key, des3_iv);	
	local http_request = http:new();
    local ok, code, headers, status, body = http_request:request {
		            url     = serverUrl,
		            method  = "POST",
		            headers = {["Content-Type"] = "application/x-www-form-urlencoded"},
		            body    = data 
	 }   

    if code ~= ngx.HTTP_OK then
	        ngx.log(ngx.ERR, "transmit to dbagent error, get result, ", "ok: ", ok, 
					         ";code: ", code, 
						     ";status: ", status, 
						     ";body: ", body,
							 ";url: ", serverUrl);   
    else
			ngx.log(ngx.NOTICE, "des3_key: ", des3_key, ", iv: ", des3_iv)
			ret, body = des3.decode(body, des3_key, des3_iv);

	        ngx.log(ngx.NOTICE, "transmit to dbagent OK, get result, ", "ok: ", ok, 
					         ";code: ", code, 
						     ";status: ", status, 
						     ";body: ", body);    
	
	end

	return ngx.exit(code);
end

--清除所有redis和ES数据
function clear_all()
	local code = handler.clear_all();	
	ngx.exit(code);
end

--对当前在线的所有用户移入下线表，清空REDIS.
function offline_all()
	ngx.exit(handler.offline_all());
end

function get_ip_zone()
	local args  = ngx.req.get_uri_args();
	local ip = args["ip"];
	if not ip then
		ngx.say("ip is need.");
		return;
	end

	local subnet_ip = util.get_subnet_ip(ip);
	local desc = g_ip_zone_dict:get(subnet_ip);
	if nil == desc then
		subnet_ip = util.get_subnet_ip2(ip);
		desc = g_ip_zone_dict:get(subnet_ip);
		if nil == desc then
			subnet_ip = util.get_subnet_ip3(ip);
			desc = g_ip_zone_dict:get(subnet_ip);
		end
	end
	
	ngx.log(ngx.NOTICE, "ip: ", ip, ", zone: ", desc);
	ngx.say(desc);
end

function stat()
	local data = {};
	data["online"] = g_data_stat_dict:get("ONLINE_CNT");
	data["offline"] = g_data_stat_dict:get("OFFLINE_CNT");
	ngx.say(cjson.encode(data));
end

function reset_stat()
	g_data_stat_dict:set("ONLINE_CNT", 0);
	g_data_stat_dict:set("OFFLINE_CNT", 0);
	ngx.exit(ngx.HTTP_OK);
end

function timeout_force_offline()
	handler.timeout_force_offline();
	ngx.exit(ngx.HTTP_OK);
end

function do_tools()
	tools.remove_expire_uuid();
end

function vidcs()
    vidc_tool.handler();
end

function ott_vidcs()
    vidc_tool.ott_handler();
end
