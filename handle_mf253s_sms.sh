#!/bin/bash

#后台运行脚本 nohup ./script.sh > output.log 2>&1 &
#检查进程：ps aux | grep script.sh
#实时查看日志：tail -f output.log


# 目标API地址
API_SET_URL="http://192.168.0.1/goform/goform_set_cmd_process"
API_GET_URL="http://192.168.0.1/goform/goform_get_cmd_process"

# 请求头设置 (JSON格式)
HEADERS=(
  "Accept:  application/json, text/javascript, */*; q=0.01"
  "Content-Type: application/x-www-form-urlencoded; charset=UTF-8"
  "Referer: http://192.168.0.1/index.html"
)

# POST数据内容 (JSON格式)
POST_DATA='{
    "isTest": "true",
    "goformId": "LOGIN",
    # echo -n "admin" | base64
    "password": "YWRtaW4="
}'


#查询短信结果，全局变量
hasLogin="false"
msgArrRst=''
shoulShowCapacity="true";


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


#bark
function notify_bark(){
    echo -e "\n发送通知 $1"
    response=$(curl -X "POST"\
         -d "title=$1" \
         -d "body=$2" \
         --silent \
         "https://api.day.app/$BARK_KEY")
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
      -d isTest=false \
      -d cmd=loginfo \
      -d multi_data=1 \
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
    if [[ "$body" =~ ok ]]; then hasLogin="true"; else hasLogin="false"; echo "登录已失效"; fi
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
    if [[ "$body" =~ 0 ]]; then echo "登录成功, $(date +'%Y-%m-%d %H:%M:%S')"; else echo "登录 $body"; fi
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
      -d isTest=false \
      -d cmd=sms_data_total \
      -d page=0 \
      -d data_per_page=500 \
      -d mem_store=1 \
      -d tags=10 \
      -d order_by="order by id desc" \
      -d _=$(date +%s%3N) \
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
    if [[ "$body" =~ number ]]; then msgArrRst="$body"; lookForUnread; else echo "$body"; fi
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
      -d _=$(date +%s%3N) \
      --silent \
      "${API_GET_URL}")

    # 解析响应结果
    #http_status=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')
    body=$(echo "$response" | sed -e 's/HTTP_STATUS:.*//')

    # 输出结果
    #echo "HTTP Status: $http_status"
    #echo "Response Body:"
    #echo "$body" | jq . 2>/dev/null || echo "$body"
    declare -A dict
    while IFS="=" read -r k v; do
      dict[$k]=$v
    done < <(echo "$body" | jq -r '. | to_entries[] | "\(.key)=\(.value)"')
    used=$(( "${dict['sms_nv_rev_total']}" + "${dict['sms_nv_send_total']}" + "${dict['sms_nv_draftbox_total']}" ))
    max="${dict['sms_nv_total']}"
    if [ "$shoulShowCapacity" == "true" ]; then echo "容量 $used / $max"; fi
    [ $(($used + 10 )) -le "$max" ] && shoulShowCapacity="false"; return;
    toDelIds=""
    delQty=$(($used - 10 )) #keep 10 left
    while read -r line; do
        toDelIds+="$line;"
    done < <(echo $msgArrRst | jq -r " .messages | .[-$delQty: ] | .[] | .id")

    deleteMessage "$toDelIds"
}


#service.deleteMessage
function deleteMessage(){
    # 执行curl命令
    # echo -e "\n删除短信 id=$1"
    response=$(curl -X "POST" \
      -H "${HEADERS[0]}" \
      -H "${HEADERS[1]}" \
      -H "${HEADERS[2]}" \
      -d "isTest=false" \
      -d "goformId=DELETE_SMS" \
      -d "msg_id=$1" \
      -d "notCallback=true" \
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
    if [[ "$body" =~ success ]]; then echo "删除成功 $1"; else echo "$body"; fi
    shoulShowCapacity="true"
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
    declare -A dict
    while IFS="=" read -r k v; do
      dict[$k]=$v
    done < <(echo $msgArrRst | jq -r ' .messages | map (select(.tag=="1")) | if length > 0 then last else {} end | to_entries[] | "\(.key)=\(.value)"')
    #${#array[@]} 返回元素数量, 获取关联数组元素数量的标准方法，与普通数组的用法一致
    [ "${#dict[@]}" -eq 0 ] && return;
    #echo ${dict["tag"]}
    #echo ${dict["id"]}
    #echo ${dict["date"]}
    # "25,08,17,23,40,33,+32" -> "08-17 23:40:33"
    msgDate=$(echo ${dict["date"]} | sed 's/\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),\([0-9]\+\),.*/\2-\3 \4:\5:\6/g')
    #echo ${dict["content"]}
    plainContent=$(decode_message ${dict["content"]})
    echo "${dict['number']}"
    echo "$plainContent"$'\n'"$msgDate"  # $'\n' 动态换行 直接\n换行没效果
    shoulShowCapacity="true"
    if [[ "$plainContent" =~ 验证密?码|流量使用提醒 ]]; then
        notify_bark  "${dict['number']}"  "$plainContent"$'\n'"$msgDate";
        deleteMessage "${dict['id']};"
    else
        setSmsRead "${dict['id']};"
    fi
}

function init(){
    getLoginStatus
    if [ "$hasLogin" == "true" ]; then getSmsCapability; getSMSMessages; else login; fi

    sleep 30
    init
}
#Bark通知服务Key, set env: export BARK_KEY="..."
if [[ -z "$BARK_KEY" ]]; then echo "未设置环境变量 BARK_KEY"; else init; fi;