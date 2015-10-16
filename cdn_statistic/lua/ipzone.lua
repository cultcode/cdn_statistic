
--[[******************************************************
File name : split.lua
Description : 
  
Version: 2.0.0
Create Date : 2015-03-18 15:46
Modified Date : 2015-03-18 15:46
Revision : none
  
Author : 刘小刚(liuxiaogang) liuxiaogang@e.hunantv.com
Company: 芒果TV 2015 版权所有
  
Please keep this mark, tks!
******************************************************--]]
module("ipzone", package.seeall);

local ffi   = require("ffi");
local C     = ffi.C

ffi.cdef[[
struct in_addr {
	        unsigned long int s_addr;
};

typedef uint32_t in_addr_t;

in_addr_t inet_addr(const char *cp);
char *inet_ntoa(struct in_addr in);
uint32_t ntohl(uint32_t netlong);
uint32_t htonl(uint32_t hostlong);
]]

function ip2num(ip)
	local num = ffi.new("in_addr_t", 0); 
	num = C.inet_addr(ip);
	if num == 4294967295 then
		return nil;
	end 
	return C.ntohl(num);
end

function num2ip(ip_num)
	local in_addr = ffi.new("struct in_addr", {});
	in_addr.s_addr = C.htonl(ip_num);

	return ffi.string(C.inet_ntoa(in_addr));
end

local function check_24(ip)
	local mask = "0.0.255.0";
	local lip = ip2num(ip);
	local lmask = ip2num(mask);

	return bit.band(lip, lmask);
end

local function get_netaddr(baseip, lip)
	local res = nil;
	if 0 == baseip then
		res = bit.band(lip, lb_mask);
	else
		res = bit.band(lip, lc_mask);
	end

	return num2ip(res);	
end

--IP/MASK 分割
local function split_ip_mask(iprange)
	local elms = util.string_split(iprange, "/");	
	return elms[1], tonumber(elms[2]); -- ip mask
end

--将包含多个网段的ip段分割成多个
function split_ip_range(iprange)
	local ip, mask = split_ip_mask(iprange);
	local istart = ip2num(ip);	
	local iend = istart + bit.lshift(1, (32-mask));
	local ret = check_24(ip);
	local step = 255;
	if 0 == ret then
		step = 65535;
	end

	g_temporary_dict:flush_all();
	for iip = istart, iend, step do
		local netaddr = get_netaddr(ret, iip);
		g_temporary_dict:set(netaddr, 1);
	end

	local keys = g_temporary_dict:get_keys();
	g_temporary_dict:flush_all();

	return keys;
end

