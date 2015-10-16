
--[[******************************************************
File name : tools.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-04-27 14:22
Modified Date : 2015-04-27 14:22
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
******************************************************--]]
module("tools", package.seeall);
 
local function __remove_expire_uuid(redis, oldVer)
	--1. 获取KEY
	local key = mgr.get_heartbeat_key(oldVer);
	local timeline = os.time() - uuid_alive_hour*3600;
	assert(redis);

	--2. 检查超时用UUID
	local res, err = redis:zrangebyscore(key, 0, timeline, 'LIMIT', 0, 10000);
	if err then
		ngx.log(ngx.ERR, "[REDIS] err: ", err, "res: ", cjson.encode(res));
		return;
	end
	
	if not res or next(res) == nil then
		return;
	end
	
	ngx.log(ngx.NOTICE, "clear uuid cnt: ", #res);

	--3. 超时UUID详情入点播详单队列
	err = mgr.del_click_detail(redis, oldVer, res);
end

function remove_expire_uuid()
	for i, host in ipairs(rdb_host_tlb)  do
		for port = rdb_port_min, rdb_port_max, 1 do

			--1. 获取redis 连接
			local redis = rdb.get_connection(host, port);
			if not redis then
				ngx.log(ngx.ERR, "[REDIS HTTP_INTERNAL_SERVER_ERROR] err: redis connect failed, host: "
						, host, ", port: ", port);
				return;
			end

			ngx.log(ngx.NOTICE, "clear edpoint: ", host, ":", port);

			--2. 旧版本
			__remove_expire_uuid(redis, true);

			--3. 新版本
			__remove_expire_uuid(redis, false);

			--4. 连接入池
			rdb.keepalive(redis);
		end
	end

	return ngx.HTTP_OK;
end
