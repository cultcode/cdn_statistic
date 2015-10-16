rdb_host_tlb={"127.0.0.1","10.200.8.2"};
rdb_host="127.0.0.1";
rdb_port=60001;
rdb_port_min = 6379;
rdb_port_max = 6380;
rdb_port_num = 2;
rdb_timeout = 30000;					--redis连接超时时间, 毫秒
rdb_keepalive_timeout = 600000;			--redis连接池idle时间, 毫秒
rdb_pool_size = 500;					--redis连接池大小
rdb_min_expire = 600;					--redis记录超时时间
rdb_max_expire = 86400;					--redis最长超时时间
redis_password="hunantv!^*cobbler";
rdb_socket = "";						--unix 域套接字路径
health_check_timeout = 180;				--redis中session超时时间，秒
const_max_uuid = 100;					--ES批量最大记录数
bulk_interval = 1;					--批量累计时间间隔
uuid_alive_hour = 0;					--uuid最大在线时间，小时

es_host = "http://10.200.8.2:9200";		--ES服务器地址
es_db_prefix = "titan_";				--ES表前缀

--注册地址
regist_url      = "http://10.200.8.3:10086/ndas/StatisticInit";

--系统配置数据库
mysql_db		= "titanCDN";
mysql_user		= "root";
mysql_password	= "root";
mysql_host		= "10.200.8.2";
mysql_port		= 3306;

version			= "0.9.0"						--系统版本
des3_key		= "";
des3_iv			= "";

--常量
STR_TIMER_ON = "timer_on";
STR_HEALTH_CHECK = "health_check_time";

enable_regist = 0;	-- 是否注册 
enable_update_= 0;  -- 是否远程更新配置
enable_redis_auth_= 1;  -- redis是否auth

ip_zone_data_file = "/opt/soft/cdn_statistic/data/ipzone.list";
ip_zone_out_file = "/opt/soft/cdn_statistic/data/ipzone_new.list";
