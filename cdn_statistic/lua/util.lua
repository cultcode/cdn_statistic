
--[[******************************************************
File name : util.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-03-11 15:35
Modified Date : 2015-03-11 15:35
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
******************************************************--]]
 
module("util", package.seeall)

--辅助函数 HTTP 
function http_send(serverUrl, Method)
	local http_request = http:new();
	local ok, code, headers, status, body = http_request:request {
				url     = serverUrl,
				method  = Method,
				headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
	}

	ngx.log(ngx.NOTICE, "transmit to ES server, url: ", serverUrl);
	if code ~= 200 then
		ngx.log(ngx.ERR, "transmit to ES error, get result: ", "ok: ", ok, 
				";code: ", code, 
				";status: ", status);	
	else
		ngx.log(ngx.NOTICE, "transmit to ES, get result: ", "ok: ", ok, 
				";code: ", code, 
				";status: ", status)
	end

	if "string" == type(code) then
		return ngx.HTTP_FORBIDDEN, body;
	end

	return code, body;
end


--辅助函数，HTTP POST数据
function post(serverUrl, post_body)
	ngx.log(ngx.NOTICE, "http post: ", cjson.encode(post_body), ", url: ", serverUrl);
	local http_request = http:new();
	local ok, code, headers, status, body = http_request:request {
			url     = serverUrl,
			method  = "POST",
			headers = {["Content-Type"] = "application/x-www-form-urlencoded"},
			body    = post_body
	}
	
	if code ~= 200 then
		ngx.log(ngx.ERR, "transmit to ES error, get result: ", "ok: ", ok, 
				";code: ", code, 
				";status: ", status, 
				";body: ", body,
				";url: ", serverUrl);	

	else
		ngx.log(ngx.NOTICE, "transmit to ES, get result: ", "ok: ", ok, 
				";code: ", code, 
				";status: ", status, 
				";body: ", body,
				";url: ", serverUrl);
	end

	if "string" == type(code) then
		return ngx.HTTP_FORBIDDEN;
	end

	return code, body;
end

function send_bulk(res, db_name, tlb_name, method)
	local data = "";
	for i, body in ipairs(res) do
		if body["uuid"] then
			assert(body["uuid"]);

			--用户下线，记录下线时间
			if db_name == mgr.get_click_detail_dbname() then
				body["disconnTime"] = os.date("%Y-%m-%dT%H:%M:%S.000",os.time());
				body["disconnTime"] = body["disconnTime"] .. "+" .. time_zone;

				--是否是health check检测出来的超时
				local timeOut = g_expire_uuid_dict:get(body["uuid"]);
				if timeOut then
					body["timeOut"] = 1;

					--从字典里删除
					g_expire_uuid_dict:delete(body["uuid"]);
				else
					body["timeOut"] = 0;
				end
			end

			--查询IP地区信息
			local ruip = body["ruip"];
			if ruip then
				local subnet_ip = util.get_subnet_ip(ruip);
				local zone = g_ip_zone_dict:get(subnet_ip);
				if not zone then
					subnet_ip = util.get_subnet_ip2(ruip);
					zone = g_ip_zone_dict:get(subnet_ip);
				end
				if not zone then
					subnet_ip = util.get_subnet_ip3(ruip);
					zone = g_ip_zone_dict:get(subnet_ip);
				end

				body["zone"] = zone;
				--拆分为isp/country/province/city/lon/lat
				if zone then
					local elms = util.string_split(zone, "|");		
					body["isp"] = elms[1];
					body["country"] = elms[2];
					body["province"] = elms[3];
					body["city"] = elms[4];
					body["longitude"] = elms[6];
					body["latitude"] = elms[7];
				end
			end

			local action = {};	
			local index = {};
			--index["_index"] = db_name;
			--index["_type"] = tlb_name;
			index["_id"] = body["uuid"];
			action[method] = index;

			data = data .. cjson.encode(action) .. "\n";
			if "delete" ~= method then
				data = data .. cjson.encode(body)  .. "\n";
			end
		end
	end

	if data == "" then
		--ngx.log(ngx.NOTICE, "db: ", db_name, ", tab: ", tlb_name, ", method: ", method, " no uuid data");
		return ngx.HTTP_OK;
	end

	--发送给ES
	local reportUrl = es_host .. "/" .. db_name .. "/" .. tlb_name ..  "/_bulk";
	local code, body = post(reportUrl, data);	

	if ngx.HTTP_OK ~= code then
		ngx.log(ngx.ERR, "[ONLINE] new online record post failed, detail: ", 
				cjson.encode(args));
	end 

	ngx.log(ngx.NOTICE, "table: ", tlb_name, 
			", method: ", method, 
			", code: ", code,
			", DATA: ", data);

	return code;
end

function string_split(s, p)
	local rt= {}
	string.gsub(s, '[^'..p..']+', function(w) table.insert(rt, w) end )
	return rt
end

function get_subnet_ip(ip) 
	local reg = "(%d+)%.(%d+)%.(%d+)%..";   

	for s1, s2, s3 in string.gmatch(ip, reg) do
		return s1 .. "." .. s2 .. "." .. s3 .. ".0";
	end

	return nil 
end

function get_subnet_ip2(ip) 
	local reg = "(%d+)%.(%d+)%..";   

	for s1, s2 in string.gmatch(ip, reg) do
		return s1 .. "." .. s2 .. ".0.0" ;
	end

	return nil 
end

function get_subnet_ip3(ip) 
	local reg = "(%d+)%..";   

	for s1, s2 in string.gmatch(ip, reg) do
		return s1 .. ".0.0.0" ;
	end

	return nil 
end

--旧版商业CDN uri格式 /sign/t/uri，定义/sign/t 为prefix
local function get_prefix(uri)
	local regex = "/(%w+)/(%w+)(/.)";
	for sign, t,  u in string.gmatch(uri, regex) do
		return "/" .. sign .. "/" .. t;
	end 

	return nil;
end

--去除前缀后的URI
function get_uri(uri)
	if not uri then
		return nil;
	end
	
	local prefix = get_prefix(uri);
	if prefix then
		uri = string.gsub(uri, prefix, "");
	end

	return uri;
end

--16进制数转10进制
function hex_to_string(hex)
	if not hex then 
		return nil;
	end

	hex = "0x" .. hex;
	local res = string.format("%d",hex);
	return res;
end

function get_ip_type(ip)
    -- must pass in a string value
    if ip == nil or type(ip) ~= "string" then
        return 0
    end 

    -- check for format 1.11.111.111 for ipv4
    local chunks = {ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")}
    if (#chunks == 4) then
        for _,v in pairs(chunks) do
            if (tonumber(v) < 0 or tonumber(v) > 255) then
                return 0
            end 
        end 
        return 1
    else
        return 0
    end 

    -- check for ipv6 format, should be 8 'chunks' of numbers/letters
    local _, chunks = ip:gsub("[%a%d]+%:?", "") 
    if chunks == 8 then
        return 2
    end 

    -- if we get here, assume we've been given a random string
    return 3
end                                                                                                                                                                                            

