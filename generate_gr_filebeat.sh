#!/usr/bin/env bash
# Author:   Marathon <jsdymarathon@itcom888.com>
# Date:     2020/8/1 6:33
# Location: Manila
# Desc:     QP生产游服生成回放日志采集filebeat实例与配置


# Source function library.
. /etc/init.d/functions


# 必要参数定义
app_name=$1
serverid=$2
host_ip=$(ifconfig | grep -E " inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)


# 参数检验
test $# -ne 2 && { echo -e "\nUsage: bash $0 app_name serverid\n\nSample: bash $0 app_zrpp_d21 21D_01\n"; exit; }
test -z "$host_ip" && { echo "无法获取当前主机IP,请检查!"; exit; }

# java go 版本过滤字段不一样，这里做个区分
game_plat=${app_name%%_*}
test "$game_plat" == "go" && filter_msg="风控日志" || filter_msg="平台当日盈亏"

# 定义filebeat实例名称
gr_filebeat_instance="filebeat-gr"
# 截取serverid前缀,用于设置field.source与索引名称
serverid_pre=${serverid%_*}


# 创建新实例程序
echo -e "\nmake ${gr_filebeat_instance} bin path..."
test -d "/usr/share/${gr_filebeat_instance}" || cp -r /usr/share/filebeat /usr/share/${gr_filebeat_instance}
test $? -eq 0 && action "" /bin/true || exit

# 创建新实例数据目录
echo -e "\nmake ${gr_filebeat_instance} data path..."
test -d "/var/lib/${gr_filebeat_instance}" || mkdir /var/lib/${gr_filebeat_instance}
test $? -eq 0 && action "" /bin/true || exit


# 创建新实例配置目录
echo -e "\nmake ${gr_filebeat_instance} config path..."
test -d "/etc/${gr_filebeat_instance}" || cp -r /etc/filebeat /etc/${gr_filebeat_instance}
test $? -eq 0 && action "" /bin/true || exit


# 生成新实例服务启停脚本
echo -e "\nmake ${gr_filebeat_instance} service scritps..."
filebeat_gr_service_file="/etc/systemd/system/multi-user.target.wants/${gr_filebeat_instance}.service"
cat > $filebeat_gr_service_file <<EOF
[Unit]
Description=${gr_filebeat_instance} log files to Logstash or directly to Elasticsearch.
Documentation=https://www.elastic.co/products/beats/filebeat
Wants=network-online.target
After=network-online.target

[Service]

Environment="BEAT_LOG_OPTS=-e"
Environment="BEAT_CONFIG_OPTS=-c /etc/${gr_filebeat_instance}/filebeat.yml"
Environment="BEAT_PATH_OPTS=-path.home /usr/share/${gr_filebeat_instance} -path.config /etc/${gr_filebeat_instance} -path.data /var/lib/${gr_filebeat_instance} -path.logs /var/log/${gr_filebeat_instance}"
ExecStart=/usr/share/${gr_filebeat_instance}/bin/filebeat \$BEAT_LOG_OPTS \$BEAT_CONFIG_OPTS \$BEAT_PATH_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
EOF
test $? -eq 0 && action "" /bin/true || exit


# 加载新实例启停脚本
echo -e "\nloading ${gr_filebeat_instance} service conf..."
systemctl daemon-reload
test $? -eq 0 && action "" /bin/true || exit


# 生成新实例配置文件
echo -e "\ncreate ${gr_filebeat_instance} config..."
cat > /etc/${gr_filebeat_instance}/filebeat.yml <<EOF
###################### Filebeat Configuration Example #########################
#=========================== Filebeat inputs =============================

filebeat.inputs:

- type: log
  enabled: true
  paths:
    - /data/software/game-app/${app_name}/${serverid}/logs/gr/*.log

  fields:
    source: prod-game-gr-${serverid_pre,,}
    ip: ${host_ip}
#============================= Filebeat modules ===============================

filebeat.config.modules:
  path: \${path.config}/modules.d/*.yml
  reload.enabled: true

#================================ Outputs =====================================
#-------------------------- Elasticsearch output ------------------------------
output.elasticsearch:
  hosts: ["10.3.18.53:9200", "10.3.18.54:9200", "10.3.18.55:9200"]
  indices:
    - index: "%{[fields.source]}-%{+yyyy.MM.dd}"
  username: "elastic"
  password: "nrjsoaP%gEcz4euym8pm"

  pipelines:
    - pipeline: "pipeline-game-record"
      when.equals:
        fields.source: "prod-game-gr-${serverid_pre,,}"

#================================ Processors =====================================

processors:
  - add_host_metadata: ~
  - drop_fields:
     fields: ["log.file.path","ecs","agent","host","input.type"]

  # 过滤敏感日志
  - drop_event:
     when:
       regexp:
          message: "${filter_msg}"

#============================== X-Pack Monitoring ===============================

monitoring.enabled: true
#monitoring.elasticsearch:
EOF
test $? -eq 0 && action "" /bin/true || exit


# 启动新实例
echo -e "\nRun ${gr_filebeat_instance} instance..."
systemctl start ${gr_filebeat_instance}
test $? -eq 0 && action "" /bin/true || exit



# 确认新实例启动状态
echo -e "\nCheck ${gr_filebeat_instance} is running..."
systemctl status ${gr_filebeat_instance}



echo -e "\n\nDone...\n\n"
