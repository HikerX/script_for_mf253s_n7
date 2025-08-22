#!/bin/bash

#后台运行脚本 nohup ./script.sh > output.log 2>&1 &
#检查进程：ps aux | grep script.sh
#实时查看日志：tail -f output.log


# 目标API地址
API_SET_URL="http://192.168.0.1/goform/goform_set_cmd_process"
API_GET_URL="http://192.168.0.1/goform/goform_get_cmd_process"

# 请求头设置 (form / JSON格式)
HEADERS=(
  "Accept:  application/json, text/javascript, */*; q=0.01"
  "Content-Type: application/x-www-form-urlencoded; charset=UTF-8"
  "Referer: http://192.168.0.1/index.html"
  "Content-Type: application/json; charset=UTF-8"
)

#查询短信结果，全局变量
hasLogin="false"
msgArrStr=''


# ==============================================
# AIG
# Unicode十六进制字符串解码工具
# 功能：过滤特殊字符后解码十六进制序列
# ==============================================

# 配置区：可过滤的特殊字符（十六进制编码）
declare -a SPECIAL_CHARS=(
    "0020"  # 空格
    "000A"  # 换行符
    "FFFD"  # Unicode替换字符
)

# 十六进制转Unicode字符
function hex_to_char() {
    local hex=$1
    local dec=$((16#$hex))
    local char=""

    # Unicode编码范围处理
    if (( dec <= 0xFFFF )); then
        printf -v char '\\u%04X' $dec
    elif (( dec <= 0x10FFFF )); then
        dec=$(( dec - 0x10000 ))
        local high=$(( 0xD800 | (dec >> 10) ))
        local low=$(( 0xDC00 | (dec & 0x3FF) ))
        printf -v char '\\u%04X\\u%04X' $high $low
    fi

    echo -e "$char"
}

# 主解码函数
function decode_message() {
    local input_str=$1
    [[ -z "$input_str" ]] && return

    # 处理十六进制序列
    while [[ $input_str =~ ([A-Fa-f0-9]{1,4}) ]]; do
        local hex=${BASH_REMATCH[1]}
        local prefix=${input_str%%$hex*}
        input_str=${input_str#*$hex}

        # 检查是否为特殊字符
        local is_special=0
        for special in "${SPECIAL_CHARS[@]}"; do
            [[ "${hex}" == "${special}" ]] && { is_special=1; break; }
        done

        # 结果拼接
        if (( is_special )); then
            printf "%s" "$prefix"
        else
            printf "%s%s" "$prefix" "$(hex_to_char "$hex")"
        fi
    done

    printf "%s" "$input_str"  # 输出剩余部分
}


#bark if [[ "$plainContent" =~ 验证密?码|流量使用提醒 ]];
function notify_bark(){
    echo " 发送通知 $1"
    # 构建JSON负载, 把device_key放入请求体，而非url
    # sound tweet 鸟鸣; telegraph 电报; calypso 卡利普索; horn 号角; chime 铃声; tiptoes 踮脚尖
    payload=$(jq -n \
        --arg title "$1" \
        --arg body "$2" \
        --arg isArchive "$3" \
        --arg sound "calypso" \
        --arg device_key "$BARK_KEY" \
        '{title: $title, body: $body, device_key: $device_key, isArchive: $isArchive, sound: $sound}' )

    response=$(curl  -X "POST"\
         -H "Content-Type: application/json; charset=UTF-8" \
         -d "$payload" \
         --silent \
         "https://api.day.app/push")
    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')
    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    #{"code":200,"message":"success","timestamp":1755502279}
    ! [[ "$body" =~ success ]] && echo "$body";
}


#service.getLoginStatus
function getLoginStatus(){
    #echo -e "\n登录状态"
    response=$(curl \
      -H "${HEADERS[0]}" \
      -H "${HEADERS[2]}" \
      -d "isTest=false" \
      -d "cmd=loginfo" \
      -d "multi_data=1" \
      -d "_=$(date +%s%3N)" \
      --silent \
      "${API_GET_URL}")

    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')

    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    #"loginfo": "" or "ok"
    if [[ "$body" =~ ok ]]; then hasLogin="true"; else hasLogin="false"; fi
}


#service.login POST
#echo -n 选项‌：禁止在输出末尾自动添加换行符（默认情况下echo会在输出后换行）。
#--write-out "HTTP_STATUS:%{http_code}"
function login(){
    # 执行curl命令
    #echo -e "\n登录CPE"
    response=$(curl -X "POST" \
      -H "${HEADERS[0]}" \
      -H "${HEADERS[1]}" \
      -H "${HEADERS[2]}" \
      -d "isTest=false" \
      -d "goformId=LOGIN" \
      -d "password=$(echo -n "admin" | base64)" \
      -d "_=$(date +%s%3N)" \
      --silent \
      "$API_SET_URL" )

    #echo "Response:"
    #echo "$response"

    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')

    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    #{"result": "0"}  {"result": "failure"}
    [[ "$body" =~ failure ]] && echo "登录 $body"
}


:<<'comment'
    page : 0,
    smsCount : 5,
    nMessageStoreType : 1, // msg saved location.  0 sim card； 1 nvram, cpe sqlite database, /etc_rw/config/sms_db/sms.db
    tags : 1, //defaut 10 all?;  短信类型 0 已读消息；1 新消息；2 已发送（未知成败）； 3 发送失败 ； 4 draft;
    orderBy : "" // default : id
comment
#service.getSMSMessages
# 执行curl命令
#--url-query cmd=sms_data_total
#--url-query cmd=sms_page_data
#--write-out "HTTP_STATUS:%{http_code}"
#3(date +%s%3N) ms timestamp
function getSMSMessages(){
    #echo -e "\n查询最近短信"
    response=$(curl \
      -H "${HEADERS[0]}" \
      -H "${HEADERS[2]}" \
      -d "isTest=false" \
      -d "cmd=sms_data_total" \
      -d "page=0" \
      -d "data_per_page=500" \
      -d "mem_store=1" \
      -d "tags=10" \
      -d "order_by=order by id desc" \
      -d "_=$(date +%s%3N)" \
      --silent \
      "${API_GET_URL}")

    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')

    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    # =~ 字符正则表达式匹配符号，这里的正则表达式更简化了
    # {messages: [{"id":"15145","content":"30109A8C8B","tag":"0","date": "25,08,15,22,23,56,+32","draft_group_id":""}]}'
    #{"sms_data_total":""}
    if [[ "$body" =~ messages ]]; then
        msgArrStr=$(echo "$body" | jq -r '.messages')
        msgArrLen=$(echo "$msgArrStr" | jq -r '. |  length')
        [ "$msgArrLen" -gt 0 ] && lookForUnread;
    else echo "$body"; fi
}


#service.setSmsRead POST
#msgIds "id1;id2;...idn;" 特别要求结尾分号不能少
function setSmsRead(){
    # 执行curl命令
    #echo -e "\n设为已读 id=$1"
    response=$(curl -X "POST" \
      -H "${HEADERS[0]}" \
      -H "${HEADERS[1]}" \
      -H "${HEADERS[2]}" \
      -d "isTest=false" \
      -d "goformId=SET_MSG_READ" \
      -d "msg_id=$1" \
      -d "tag=0" \
      -d "_=$(date +%s%3N)" \
      --silent \
      "$API_SET_URL" )

    #echo "Response:"
    #echo "$response"

    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')

    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    ! [[ "$body" =~ success ]] && echo "$body";
}

:<<'comment'
{
    "sms_nv_total": "100",
    "sms_nv_rev_total": "22",
    "sms_nv_send_total": "4",
    "sms_nv_draftbox_total": "0",
    "sms_sim_total": "50",
    "sms_sim_rev_total": "0",
    "sms_sim_send_total": "0",
    "sms_sim_draftbox_total": "0"
}
comment
#service.getSmsCapability
function getSmsCapability(){
    #echo -e "\n查询容量"
    response=$(curl \
      -H "${HEADERS[0]}" \
      -H "${HEADERS[2]}" \
      -d isTest=false \
      -d cmd=sms_capacity_info \
      -d "_=$(date +%s%3N)" \
      --silent \
      "${API_GET_URL}")

    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')

    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    #declare -A dict; #使用 关联数组 和 进程替换 ，在 termux (an)测试通过，在iSH(iOS)测试失败
    sms_nv_size=$(echo "$body" | jq -r '.sms_nv_total') # possible "null"
    sms_nv_rev_qty=$(echo "$body" | jq -r '.sms_nv_rev_total')
    sms_nv_send_qty=$(echo "$body" | jq -r '.sms_nv_send_total')
    sms_nv_draftbox_qty=$(echo "$body" | jq -r '.sms_nv_draftbox_total')
    used=$(( "$sms_nv_rev_qty" + "$sms_nv_send_qty" + "$sms_nv_draftbox_qty" ))
    ( [[ "$sms_nv_size" == "null" ]] || [ $(($used + 10)) -le "$sms_nv_size" ] ) && return;
    delQty=$(( "$used" - 10 )) #keep 10 left
    echo "容量 $used / $sms_nv_size, 删除最早 $delQty 条, $(date +'%Y-%m-%d %H:%M:%S')"
    toDelIds=$(echo "$msgArrStr" | jq -r ".[-$delQty: ] | [.[].id] | join(\";\")")
    #echo "toDelIds: $toDelIds"
    #结尾必须补上';'
    deleteMessage "$toDelIds;"
}


#service.deleteMessage
function deleteMessage(){
    # 执行curl命令
    echo "删除短信 $1"
    response=$(curl -X "POST" \
      -H "${HEADERS[0]}" \
      -H "${HEADERS[1]}" \
      -H "${HEADERS[2]}" \
      -d "isTest=false" \
      -d "goformId=DELETE_SMS" \
      -d "msg_id=$1" \
      -d "notCallback=true" \
      -d "_=$(date +%s%3N)" \
      --silent \
      "$API_SET_URL" )

    #echo "Response:"
    #echo "$response"

    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')

    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    ! [[ "$body" =~ success ]] && echo "$body";
}

:<<'comment'
{
    "id": "15150",
    "number": "106589666700",
    "content": "30109A8C8BC15BC67...",
    "tag": "0",
    "date": "25,08,17,00,51,03,+32",
    "draft_group_id": ""
}
comment
function lookForUnread(){
    #echo -e "\n寻找未读"
    msg_unread=$(echo "$msgArrStr" | jq -r ' map(select(.tag=="1")) | if length > 0 then last else "" end')
    #echo "msg_unread: $msg_unread"
    [[ -z $msg_unread ]] && return;
    msg_id=$(echo "$msg_unread" | jq -r '.id')
    msg_number=$(echo "$msg_unread" | jq -r '.number')
    msg_content=$(echo "$msg_unread" | jq -r '.content')
    msg_tag=$(echo "$msg_unread" | jq -r '.tag')
    msg_date=$(echo "$msg_unread" | jq -r '.date')
    msg_draft_group_id=$(echo "$msg_unread" | jq -r '.draft_group_id')

    #echo ${msg_id}
    #echo ${msg_tag}
    #echo ${msg_date}
    #echo ${msg_content}
    # "25,08,17,23,40,33,+32" -> "2025-08-17 23:40:33"
    msgDate=$(echo "$msg_date" | sed "s/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),.*/$(date +%Y)-\2-\3 \4:\5:\6/g")
    plainContent=$(decode_message "$msg_content")
    echo "[新]$msg_number, $plainContent $msgDate"  # $'\n' 动态换行 直接\n换行没效果
    # isArchive="0" ; bark是否存档, 验证码不存档
    if [[ "$plainContent" =~ 验证密?码 ]]; then deleteMessage  "$msg_id;" ; notify_bark  "$msg_number"  "$plainContent"$'\n'"$msgDate"  "0";
    elif [[ "$plainContent" =~ 流量(使用|用尽)提醒|话费账单 ]]; then setSmsRead  "$msg_id;"; notify_bark  "$msg_number"  "$plainContent"$'\n'"$msgDate"  "1";
    elif [[ "$plainContent" =~ 您已免费获得中国移动.*|到账提醒|(话费|流量)兑换券使用成功|公益短信|公安|应急|爱卫办 ]]; then deleteMessage  "$msg_id;";
    else setSmsRead "$msg_id;"
    fi
}

function init(){
    getLoginStatus
    #优先获取短信列表，再查询容量;假设当前容量已满，需要知道短信id，才能进行删除操作，
    if [ "$hasLogin" == "true" ]; then getSMSMessages; getSmsCapability; else login; fi
    sleep 5
    init
}
#Bark通知服务Key, set env: export BARK_KEY="..."
if [[ -z "$BARK_KEY" ]]; then echo "未设置环境变量 BARK_KEY"; else init; fi;