# Huawei AppGallery Connect (Remote Config) keep rules — shipped as
# consumer ProGuard rules so apps depending on this plugin do not need to
# duplicate them.
-keep class com.huawei.agconnect.** { *; }
-dontwarn com.huawei.agconnect.**
-keep class com.huawei.hmf.** { *; }
-dontwarn com.huawei.hmf.**
