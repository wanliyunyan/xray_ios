# xray核心的简单例子
实现了最基础的功能，安装以后首次使用需要从别的地方复制配置，类似 **vless://id@ip:port?security=none&encryption=none&type=tcp** 这样的链接，然后从剪切板粘贴进来，或者扫描二维码，配置会保存到 **UserDefaults**，再次使用的时候直接点击连接就可以  

## 地理文件
如果您的网络可以自由的访问github，那么可以直接点击**地理文件**下载，下载成功以后会显示在页面上。如果有限制，建议先连接vpn，之后再点击**地理文件**下载

## LibXrayPing
启动**xray**以后，就不能使用**LibXrayPing**方法，程序会崩，所以连接中的时候隐藏了**点击获取网速**，同时**LibXrayPing**方法只能用一次，具体原因参考[issue](https://github.com/XTLS/libXray/issues/43)

## 测试机型
iphone 15 plus，系统 ios 17.6.1 和 18  
iphone 12，系统 ios 17.6.1  
低于17.6.1的版本我没有测试过，很抱歉我就只有一台ios17.6.1的iphone  
ios15和ios16参考这个[issue](https://github.com/wanliyunyan/xray_ios/issues/14#issuecomment-2651015275) 

## 测试链接
**vless**链接，其它的链接都没有测试过，所以有什么问题，我也不知道

## 格式化
```shell
swiftformat .
```

## ipv6
不确定是否能工作，我不知道如何测试ipv6
