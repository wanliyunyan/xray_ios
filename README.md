# xray核心的ios例子
实现了最基础的功能，安装以后首次使用需要从别的地方复制配置，类似 **vless://id@ip:port?security=none&encryption=none&type=tcp** 这样的链接，然后从剪切板粘贴进来，配置会保存到 **UserDefaults**，再次使用的时候直接点击连接就可以  

## LibXrayPing
启动**xray**以后，就不能使用**LibXrayPing**方法，程序会崩，所以连接中的时候隐藏了**点击获取网速**，同时**LibXrayPing**方法只能用一次，具体原因参考[issue](https://github.com/XTLS/libXray/issues/43)

## 测试机型
iphone 15 plus，系统 ios 17.6.1 和 18  
iphone 12，系统 ios 17.6.1

## 测试连接
**vless**连接
