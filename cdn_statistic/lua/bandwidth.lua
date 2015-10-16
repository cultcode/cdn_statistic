--[[******************************************************
File name : bandwidth.lua
Description :

Version: 2.0.0
Create Date : 2015-07-20 10:07
Modified Date : 2015-07-20 10:07
Revision : none

Author : 邵灿(shaocan) shaocan@e.hunantv.com
Company: 芒果TV 2015 版权所有

Please keep this mark, tks!
******************************************************--]]

module("bandwidth",package.seeall)

function insert()
	local body = ngx.req.get_body_data();
	local info = {};
	
	if not body then
		ngx.log(ngx.ERR,"data is null");
		ngx.exit(ngx.HTTP_FORBIDDEN);
	end
	
	local ret, body = des3.decode(body, des3_key, des3_iv);
	ngx.log(ngx.NOTICE,"ret=",ret,",body=",body);
	
	if ret == false then
		ngx.log(ngx.ERR,"data error");
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end
	
	body = cjson.decode(body);
	
	if body["nodeId"] ~= nil and body["date"] ~= nil and body["bandwidth"] ~= nil then
		info["nodeId"] = body["nodeId"];
		info["date"] = body["date"];
		info["bandwidth"] = body["bandwidth"];
	else
		ngx.log(ngx.ERR,"param error");
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end
	
	for i,v in pairs(info.bandwidth) do
		info["pno"] = v.pno;
		info["data"] = v.data;
		insert_db(info);
	end
	
	g_bandwidth_stat_dict:incr("COUNT",1)
	ngx.log(ngx.NOTICE,"success");
	ngx.exit(ngx.HTTP_OK)
end

function insert_db(info)
	local sql = "insert into bandwidth_pno_1m(datatime,nodeId,domainId,bandwidth) values('" .. info["date"] .. "'," .. info["nodeId"] .."," .. info["pno"] .. "," .. info["data"] ..")";
	
	db_instance = db_pool.get_connection(db_name);
	local res,err = db_pool.query(db_instance,sql);
	db_pool.keepalive(db_instance);
	if err then
		ngx.log(ngx.ERR,"res=",cjson.encode(res),",sql=",sql);
	end
end

function get_count()
	local count = g_bandwidth_stat_dict:get("COUNT")
	ngx.say("Current API Request Count:" .. count);
	ngx.exit(ngx.HTTP_OK)
end

--[[
	95
	http://XXXX/CostManagerment/maxbd/
	{
		"epochTime": "2015-07-28 11:00:03",
		"datadate": "2015-07-27",
		"count": 83,
		"data": [
			{
				"idcname": "北京电信",
				"netname": "1",
				"peak": 9592,
				"costpeak": 8242.663
			}
		]
	}
	
	SELECT COUNT(1) FROM cost_price WHERE `iscurrent`=1 AND iscalc=1
--]]
function maxbd_insert()
	local body = ngx.req.get_body_data();
	local info = {};
	
	if not body then
		ngx.log(ngx.ERR,"data is null");
		say_to_web(0,"data is null");
		ngx.exit(ngx.HTTP_FORBIDDEN);
	end
	
	--[[local ret, body = des3.decode(body, des3_key, des3_iv);
	ngx.log(ngx.NOTICE,"ret=",ret,",body=",body);
	
	if ret == false then
		ngx.log(ngx.NOTICE,"data error");
		say_to_web(0,"data decode error");
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end
	]]
	
	s1,s2=string.find(body,"{");
	if s1 == nil then
		ngx.log(ngx.ERR,"json error");
		say_to_web(0,"json decode error");
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end
	
	body = cjson.decode(body)
	
	if body["epochTime"] ~= nil and body["datadate"] ~= nil and body["data"] ~= nil then
		info["epochTime"] = body["epochTime"];
		info["datadate"] = body["datadate"];
		info["data"] = body["data"];
	else
		ngx.log(ngx.ERR,"param error");
		say_to_web(0,"param error");
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end
	
	-- 校验数据条数是否符合要求
	local sql = "SELECT COUNT(1) as count FROM cost_price WHERE iscurrent=1 AND iscalc = 1";
	db_instance = db_pool.get_connection(db_name);
	local res = db_pool.query(db_instance,sql);
	
	--ngx.log(ngx.ERR,"res111=",cjson.encode(res));
	
	--[[if tonumber(res[1]["count"]) ~=  #info.data then
		ngx.log(ngx.NOTICE,"data count error");
		say_to_web(0,"data count error");
		ngx.exit(ngx.HTTP_FORBIDDEN)
	end]]
	
	ngx.log(ngx.NOTICE,"count=",#info.data,",data=",cjson.encode(info.data));
	
	for i,v in pairs(info.data) do
		info["idcname"] = v.idcname;
		info["netname"] = v.netname;
		info["peak"] = v.peak;
		info["costpeak"] = v.costpeak;
		insert_maxbd_db(info);
	end
	
	say_to_web(1,"success");
	ngx.log(ngx.NOTICE,"success");
	ngx.exit(ngx.HTTP_OK)
end

function insert_maxbd_db(info)
	local sql = "insert into cost_nw(datadate,idcname,netname,peak,costpeak) values('" .. info["datadate"] .. "','" .. info["idcname"] .."','" .. info["netname"] .. "'," .. info["peak"] .. "," .. info["costpeak"] ..")";
	local db_name = "CostCDN";	
	db_instance = db_pool.get_connection(db_name);
	local res,err = db_pool.query(db_instance,sql);
	db_pool.keepalive(db_instance);
	if err then
		ngx.log(ngx.ERR,"res=",cjson.encode(res),"sql=",sql);
	end
end

function say_to_web(status,desc)
	local info ={};
	info["Status"] = status;
	info["StatusDesc"] = desc;
	local json = cjson.encode(info);
	ngx.log(ngx.NOTICE,json);
	ngx.say(json);
end
