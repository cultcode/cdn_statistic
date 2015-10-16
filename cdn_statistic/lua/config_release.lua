rdb_host_tlb={"10.100.1.128"};
rdb_host="10.100.1.128";
rdb_port=8888;
rdb_port_min = 8888;
rdb_port_max = 8888;
rdb_port_num = 1;
rdb_timeout = 60000;					--redis连接超时时间, 毫秒
rdb_keepalive_timeout = 600000;			--redis连接池idle时间, 毫秒
rdb_pool_size = 15;					--redis连接池大小
rdb_min_expire = 6000;                  	--redis记录超时时间
rdb_max_expire = 86400;                	--redis最长超时时间
redis_password="hunantvcobbler168";
rdb_socket = "";						--unix 域套接字路径
health_check_timeout = 180;				--redis中session超时时间，秒
const_max_uuid = 500;					--ES批量最大记录数
bulk_interval = 0.5;					--批量累计时间间隔
uuid_alive_hour = 4;					--uuid最大在线时间，小时

es_host = "http://10.100.3.213:9200";	--ES服务器地址
es_db_prefix = "titan_";				--ES表前缀

--注册地址
regist_url      = "http://10.200.8.3:10086/ndas/StatisticInit";

--系统配置数据库
mysql_db		= "titanCDNData";
mysql_user		= "costadmin";
mysql_password		= "cost!safe";
mysql_host		= "10.100.10.38";
mysql_port		= 3306;
vidc_mysql_db       = "titanCDN";
vidc_mysql_user     = "titan_readonly";
vidc_mysql_password = "titan_cdnreadonly"; 
vidc_mysql_host     = "10.100.10.38";
vidc_mysql_port     = 3306;

version			= "0.9.0"						--系统版本
des3_key		= "D^=^vGfAdUTixobQP$HhsTsa";
des3_iv			= "aVtsvC#S";

mysql_connection_idle_time = 300;
mysql_connection_pool_size = 300;


--常量
STR_TIMER_ON = "timer_on";
STR_HEALTH_CHECK = "health_check_time";

enable_regist = 0;	-- 是否注册 
enable_update_= 0;  -- 是否远程更新配置
enable_redis_auth_= 0;  -- redis是否auth

ip_zone_data_file = "/opt/soft/cdn_statistic/data/ipzone.list";
ip_zone_out_file = "/opt/soft/cdn_statistic/data/ipzone_new.list";
