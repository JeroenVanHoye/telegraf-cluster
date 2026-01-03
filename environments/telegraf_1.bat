set LOCAL_NAME=telegraf_1
set LOCAL_CLUSTER_PORT=8086
set CLUSTER_TOKEN=x
set CLUSTER_HEARTBEAT_INTERVAL=1s
telegraf.exe --config redundancy.conf
