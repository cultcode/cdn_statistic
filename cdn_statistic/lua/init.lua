
--[[******************************************************
File name : init.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-02-10 09:26
Modified Date : 2015-02-10 09:26
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
******************************************************--]]
 
bit             	= require("bit");
rdb			= require("rdb_pool");
resty_url		= require("resty.url");
http			= require("resty.http");
resty_mysql		= require("resty.mysql");
luasql			= require("luasql.mysql");
resty_redis     	= require("resty.redis");
conhash			= require("chash");
cjson			= require("cjson");
des3			= require("des3");
handler			= require("handler");
mgr				= require("manager");
util			= require("util");
ipzone			= require("ipzone");
mmh3			= require("murmurhash3");
tools			= require("tools");
db_pool			= require("db_pool");
vidc_tool       	= require("vidc_tool");

--系统发布配置
local ENVI_RELEASE   = 1; -- 线上版本
local ENVI_DEBUG	 = 2; --调试版本

--运行环境 发布or调试
local ENVI = ENVI_RELEASE;

--系统配置
g_data_param_dict     = ngx.shared.data_param_dict; 
--系统全局变量
g_data_stat_dict	  = ngx.shared.data_stat_dict;
--IP库
g_ip_zone_dict		  = ngx.shared.ip_zone_dict;
--作为map用的临时字典
g_temporary_dict	  = ngx.shared.temporary_dict;
--记录三分钟内超时UUID的字段
g_expire_uuid_dict	  = ngx.shared.expire_uuid_dict;
--保存带宽统计
g_bandwidth_stat_dict = ngx.shared.bandwidth_stat_dict;

if ENVI == ENVI_RELEASE then
	dofile("/opt/soft/cdn_statistic/cdn_statistic/lua/config_release.lua");
else
	dofile("/opt/soft/cdn_statistic/cdn_statistic/lua/config.lua");
end

function test_rdb_port_conhash()
	local uuid = "my_hash_key";
	local upstream = conhash.get_upstream(uuid);

	ngx.log(ngx.NOTICE, "get: ", upstream);
end

--初始化redis端口
function init_rdb_port_conhash()
	for port = rdb_port_min, rdb_port_max, 1 do
		conhash.add_upstream(tostring(port));		
	end

	test_rdb_port_conhash();

	rdb_port_num = rdb_port_max - rdb_port_min + 1;
end

init_rdb_port_conhash();

--test_rdb_port_conhash();
	
--加载系统配置
function rows (connection, sql_statement)
	 local cursor = assert (connection:execute (sql_statement))
	 return function ()
	    return cursor:fetch()
	 end
end

function load_sys_param(mysql_conn)
	local sql = "select parmName, parmValue from sm_parm;";
	
	local mysql = luasql.mysql();
	local db_instance = mysql:connect(mysql_db,
			mysql_user,
			mysql_password,
			mysql_host,
			mysql_port);
	local res = db_pool.rows(db_instance,sql);
	
	for name, value in res do
		if name == "des3_key" then
			g_data_param_dict:set(name, value);
		elseif name == "des3_iv" then
			g_data_param_dict:set(name, value);
		end

		ngx.log(ngx.NOTICE, "key: ", name, ", value: ", value);
	end
	
	--db_pool.keepalive(db_instance);
end

local function test_ip_zone()
	local ip = "222.240.176.11";
	local subnet_ip = util.get_subnet_ip(ip);
	local desc = g_ip_zone_dict:get(subnet_ip);
	if nil == desc then
		subnet_ip = util.get_subnet_ip2(ip);
		desc = g_ip_zone_dict:get(subnet_ip);
		print(desc);	
	else
		print(desc);	
	end
end

local function init_ip_zone()
	local rfile=io.open(ip_zone_data_file, "r") --读取文件(r读取)  
	assert(rfile)								--打开时验证是否出错  

	for str in rfile:lines() do						--一行一行的读取  
		local elms = util.string_split(str, " ");	--ip/mask
		local subnet_ips = ipzone.split_ip_range(elms[1]);
		for i, subnet_ip in ipairs(subnet_ips) do
			g_ip_zone_dict:set(subnet_ip, elms[6] .. "|" 
								   .. elms[2] .. "|" .. elms[3] .. "|" .. elms[4] .. "|" 
								   .. elms[9] .. "|" .. elms[7] .. "|" .. elms[8]);
			--ngx.log(ngx.NOTICE, "== subnet: ", subnet_ip);

		end
--[[
		local subnet_ip = util.get_subnet_ip(tostring(elms[1]));
		g_ip_zone_dict:set(subnet_ip, elms[6] .. "|" 
							   .. elms[2] .. "|" .. elms[3] .. "|" .. elms[4] .. "|" 
							   .. elms[9] .. "|" .. elms[7] .. "|" .. elms[8]);
--]]
	end  

	rfile:close();

	--测试ip库
	test_ip_zone();
end

--初始化系统全局变量
local function init_stat()
	g_data_stat_dict:set(STR_TIMER_ON, 0);		--定时器是否启动
	g_data_stat_dict:set(STR_HEALTH_CHECK, 0);	--健康度检查时间
	
	g_data_param_dict:set("des3_key", des3_key);
	g_data_param_dict:set("des3_iv", des3_iv);

	--上下线次数
	g_data_stat_dict:set("ONLINE_CNT", 0);
	g_data_stat_dict:set("OFFLINE_CNT", 0);
	
	g_bandwidth_stat_dict:set("COUNT",0);
	
	g_data_stat_dict:set("mysql_connect_fail_count",0);
end

if 1 == enable_update then
	--[[local mysql = luasql.mysql();
	local mysql_conn = mysql:connect(mysql_db,
			mysql_user,
			mysql_password,
			mysql_host,
			mysql_port);--]]


	--assert(mysql_conn);

	load_sys_param(mysql_conn);

	--[[if mysql_conn then
		mysql_conn:close();
	end
	mysql:close();--]]
end

--初始化系统状态和配置
init_stat();

--初始化IP库
--//A类地址掩码，网络地址(8) + 主机地址(24), 网络地址最高位必须为0 范围1.0.0.0-127.255.255.255
--local A_MASK = "255.0.0.0"; 
--//B类地址掩码，网络地址(16) + 主机地址(16), 网络地址最高位必须为10 范围128.0.0.0-191.255.255.255
local B_MASK = "255.255.0.0"; 
--//C类地址掩码，网络地址(24) + 主机地址(8), 网络地址最高位必须为110 范围192.0.0.0-223.255.255.255
local C_MASK = "255.255.255.0"; 
--la_mask = ip2num(A_MASK);
lb_mask = ipzone.ip2num(B_MASK);
lc_mask = ipzone.ip2num(C_MASK);

init_ip_zone();

--获取系统时区
local gmt=os.date("*t", 0);
time_zone = 8;--tostring(gmt.hour);
time_zone = "0"..time_zone .. ":00";

--test
for i, host in ipairs(rdb_host_tlb)  do
	for port = rdb_port_min, rdb_port_max, 1 do
		local hostPort = host .. ":" .. tonumber(port);
		ngx.log(ngx.NOTICE, "[REDIS] rdb endpoint：", hostPort);
	end
end

