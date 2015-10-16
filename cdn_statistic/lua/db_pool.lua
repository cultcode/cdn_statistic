--[[
****************************************************
File name : db_pool.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-01-25 21:50
Modified Date : 2015-01-25 21:50
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
****************************************************
]]--

module("db_pool", package.seeall)

---------------------------------------------------------------------------------
------ 从连接池获取数据库连接
---------------------------------------------------------------------------------
function get_connection(db_name)
	if db_name == nil then
		db_name = mysql_db;
	end
	local db = resty_mysql:new();
	db:set_timeout(mysql_timeout);

	local ok, err, errno, sqlstate = db:connect({host = mysql_host,port = mysql_port,database = db_name,user = mysql_user,	password = mysql_password});
	
	if not ok then
		ngx.log(ngx.ERR, "[DB] failed to connect: ", err, ": ", errno, " ",sqlstate,"host:", mysql_host, "port:", mysql_port);
		error_incr();
		return nil;
	end

	return db;
end

---------------------------------------------------------------------------------
------ 将据库连接放回连接池
---------------------------------------------------------------------------------
function keepalive(db)
	if nil == db then
		ngx.log(ngx.ERR, "[DB] set_keepalive failed, ");
		error_incr();
		return;
	end

	if mysql_connection_idle_time < 300 then
		mysql_connection_idle_time = 300;
	end

	if mysql_connection_pool_size < 300 then
		mysql_connection_pool_size = 300;
	end

	ok, err = db:set_keepalive(mysql_connection_idle_time,mysql_connection_pool_size);
	if not ok then
		ngx.log(ngx.ERR, "[DB] set_keepalive failed, ", err);
		error_incr();
	end
end

---------------------------------------------------------------------------------
------ 执行一个查询
---------------------------------------------------------------------------------
function query(db, sql)
	local res, err, errno, sqlstate = db:query(sql);
	if not res then
		ngx.log(ngx.ERR, "[QUERY] bad result: ",err, ": ", errno, ": ", sqlstate, ", sql: ", sql);
		error_incr();
		return false;
	end
	return res,err;
end

--更新错误统计
function error_incr()
	g_data_stat_dict:set("mysql_connect_fail_time", os.time());
	g_data_stat_dict:incr("mysql_connect_fail_count", 1);
end
