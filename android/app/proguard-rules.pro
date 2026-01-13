# jaudiotagger uses AWT and ImageIO which are not available on Android.
# We don't use the methods that require them, so we can safely ignore these warnings.
-dontwarn java.awt.**
-dontwarn javax.imageio.**
