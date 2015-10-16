
--[[******************************************************
File name : rdb.lua
Description : 

Version: 2.0.0
Create Date : 2015-02-10 09:23
Modified Date : 2015-02-10 09:23
Revision : none

Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有

Please keep this mark, tks!
******************************************************--]]
module("rdb_pool", package.seeall);

--连接特定端口
function get_connection(host, port)
	local redis = resty_redis:new();
	redis:set_timeout(rdb_timeout)
	if host == nil then
		host = rdb_host;
	end
	if port == nil then
		port = rdb_port;
	end	
	--ngx.log(ngx.NOTICE,"host=",host,",port=",port);
	local ok, err = redis:connect(host, port);
	--local ok, err = redis:connect("10.100.3.68", 8888);
	if not ok then
		ngx.log(ngx.ERR, "[RDB CONNECT] failed to connect: ", err, 
		", host: ", host, ", port: ", port);

		return nil;
	end

	if enable_redis_auth_== 1 then
		local res, err = redis:auth(redis_password);
		if not res then
			ngx.log(ngx.ERR, "failed to authenticate: ", err)
			return nil;
		end
	end

	return redis;
end

--获取domain socket
function get_unix_socket()
	local redis = resty_redis:new();
	redis:set_timeout(rdb_timeout);

	local ok, err = redis:connect(rdb_socket);
	if not ok then
		ngx.log(ngx.ERR, "[RDB CONNECT] failed to connect: ", err);
		return nil;
	end

	local res, err = redis:auth(redis_password);
	if not res then
		ngx.log(ngx.ERR, "failed to authenticate: ", err)
		return nil;
	end

	return redis;
end

--关闭连接
function close(redis)
	return redis:close();
end

-- 将rdb的redis连接放入连接
function keepalive(redis)
	if not redis then
		return;
	end

	local ok, err = redis:set_keepalive(rdb_keepalive_timeout, rdb_pool_size);
	if not ok then
		ngx.log(ngx.ERR, "[RDB KEEPALIVE] failed to keepalive: ", err);
		return false;
	else
		ngx.log(ngx.NOTICE, "[RDB KEEPALIVE] keepalive OK");
	end

	return true;
end
