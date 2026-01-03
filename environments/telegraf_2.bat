set LOCAL_NAME=telegraf_2
set LOCAL_CLUSTER_PORT=8087
set CLUSTER_TOKEN=x
set CLUSTER_HEARTBEAT_INTERVAL=1s
telegraf.exe --config redundancy.conf
