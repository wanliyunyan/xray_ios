# xray核心的简单例子
这个项目只是展示了libxray的基础使用方式  
This project only demonstrates the basic usage of libxray  

实现了最基础的功能，安装以后首次使用需要从别的地方复制配置，类似 **vless://id@ip:port?security=none&encryption=none&type=tcp** 这样的链接，然后从剪切板粘贴进来，或者扫描二维码，配置会保存到 **UserDefaults**，再次使用的时候直接点击连接就可以  

The implementation includes only the most basic functionality. Upon first use after installation, the user needs to copy a configuration from elsewhere, similar to **vless://id@ip:port?security=none&encryption=none&type=tcp**, then paste it from the clipboard or scan a QR code. The configuration will be saved to **UserDefaults**, allowing the user to simply click 连接 for subsequent uses.

## 地理文件
如果您的网络可以自由的访问github，那么可以直接点击**地理文件**下载，下载成功以后会显示在页面上。如果有限制，建议先连接vpn，之后再点击**地理文件**下载  

If your network can freely access GitHub, you can directly click **地理文件** to download them. Once downloaded successfully, they will be displayed on the page. If there are restrictions, it is recommended to first connect to a VPN and then click **地理文件** to download.

## LibXrayPing
启动**xray**以后，不能使用**LibXrayPing**方法  

After starting **Xray**, the **LibXrayPing** method can no longer be used.  

## 测试机型
iphone 15 plus，系统 ios 17.6.1 和 18  
iphone 12，系统 ios 17.6.1  
低于17.6.1的版本我没有测试过，很抱歉我就只有一台ios17.6.1的iphone  
I have not tested versions below 17.6.1. Apologies, as I only have an iPhone running iOS 17.6.1.  
代码应该支持 iOS15 和 iOS 16  
The code should support iOS 15 and iOS 16. 
[ios16无法使用](https://github.com/wanliyunyan/xray_ios/issues/14#issuecomment-2651015275) [ios 16 support](https://github.com/wanliyunyan/xray_ios/issues/16)

## 测试链接
**vless**链接，其它的链接都没有测试过，所以有什么问题，我也不知道  

Only VLESS links have been tested. Other types of links have not been tested, so I am unsure about potential issues.

## 格式化
```shell
swiftformat .
```

## ipv6
我没有ipv6的网络，所以我没法调试代码，主要是修改listen  

I do not have an IPv6 network, so I am unable to debug the code. The main modification involves adjusting the listen setting.
This project only demonstrates the basic usage of libxray.
