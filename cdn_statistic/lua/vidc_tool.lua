module("vidc_tool", package.seeall)

local function rows (luasql_conn, sql_statement)
    local cursor = assert (luasql_conn:execute (sql_statement))
    return function ()
        return cursor:fetch({}, "a")
    end 
end

local function load_vidcs(mysql_conn)
    local sql="SELECT nodeName, idcname FROM `sm_idc` a JOIN `sm_node` b ON a.`idcId`=b.`idcId`";
    local res = {}; 
    for rr in rows(mysql_conn, sql)  do  
          table.insert(res, rr);
    end 
    return res;
end

function handler()
    --获取数据库连接
    local mysql = luasql.mysql();    
    local mysql_conn = mysql:connect(
            vidc_mysql_db,
            vidc_mysql_user,
            vidc_mysql_password,
            vidc_mysql_host,
            vidc_mysql_port);

    assert(mysql_conn);
    --设置字符集
    local sql="set names 'utf8';"; 
    local result = mysql_conn:execute(sql);
    ngx.log(ngx.NOTICE, "set mysql charset utf8 OK");

    local vidcs = load_vidcs(mysql_conn);

    if mysql_conn then
        mysql_conn:close();
    end 
    mysql:close();                                                                                                                                                                                        
    ngx.header["Content-Type"] = "application/json";
    ngx.say(cjson.encode(vidcs));
end

local function load_ott_vidcs(mysql_conn)
    local sql="SELECT b.`nodeName`, a.`regionName` FROM `sm_region` a JOIN `vod_node` b ON a.`regionId`=b.`regionId`";
    local res = {}; 
    for rr in rows(mysql_conn, sql)  do  
          table.insert(res, rr);
    end 
    return res;
end


function ott_handler()
    --获取数据库连接
    local ott_mysql_db = "ImgoCDN";
    local ott_mysql_user = "cdn_stat";
    local ott_mysql_password = "er9siD65dk3";
    local ott_mysql_host = "192.168.9.36";
    local ott_mysql_port = 3306; 

    local mysql = luasql.mysql();    
    local mysql_conn = mysql:connect(
            ott_mysql_db,
            ott_mysql_user,
            ott_mysql_password,
            ott_mysql_host,
            ott_mysql_port);

    assert(mysql_conn);
    --设置字符集
    local sql="set names 'utf8';"; 
    local result = mysql_conn:execute(sql);
    ngx.log(ngx.NOTICE, "set mysql charset utf8 OK");

    local vidcs = load_ott_vidcs(mysql_conn);

    if mysql_conn then
        mysql_conn:close();
    end 
    mysql:close();                                                                                                                                                                                        
    ngx.header["Content-Type"] = "application/json";
    ngx.say(cjson.encode(vidcs));
end

