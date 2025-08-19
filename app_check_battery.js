
/**
 * 检查设备电量
 * 更新时间：2023/04/01
 * 备注： 本页的 api 只需要手机号即可
 * cron "5 0 6-22/4 * * *" script-path=app_check_battery.js
 * const $ = new Env('检查设备电量');
 */
import os from "os"
import { exec } from 'child_process';

/**
 * 获取本机ipv4 地址，简单过滤虚拟机网卡
 */

const getIPv4Adress = function () {
    let nets = os.networkInterfaces()
    for (let dev in nets) { // wlan, loopback, Ethernet
        if (dev.search(/virtual/i) > -1) continue;
        let cfgList = nets[dev]
        for (let cfg of cfgList) {
            //console.log(cfg)
            let { address, family, internal } = cfg
            if (family == "IPv4" && internal == false && address != "127.0.0.1") { // internal loopback 127.0.0.1
                return address
            }
        }
    }
}

console.log(getIPv4Adress())
/**
 * 设备电池监控
 */
const checkBattery = function () {
    console.log("\n 检查设备电量:")
    let command = `cat /sys/class/power_supply/battery/capacity`;
    exec(command, (err, stdout, stderr) => {
        if (stdout > 20) {
            console.log("电量充足", stdout)
        } else {
            let capacity = stdout
            console.log("电量低", capacity)

            // 检查是否正在充电
            let command = `cat /sys/class/power_supply/battery/status`;
            exec(command, (err, stdout, stderr) => {
                if (stdout && /^Charging/.test(stdout)) { // "Charging" "No charging"
                    console.log("正在充电", stdout)
                } else {
                    console.log("提醒充电", capacity)
                    if (process.env.QL_BRANCH != undefined) {
                        QLAPI.notify(`电量低 🔋❗${capacity}`, getIPv4Adress())                        
                    }                    
                    
                }
                if (err || stderr) {
                    console.error(err || stderr);
                }
            });
        }
        if (err || stderr) {
            console.error(err || stderr);
        }
    });
}


const platform = process.platform
if (platform && platform.match(/linux$/i)) { // 
    //console.log(SHELL)
    checkBattery();
} else {
    console.log("not linux")
}