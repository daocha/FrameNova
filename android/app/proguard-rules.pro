# Project files are stored as JSON through kotlinx.serialization.
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class com.framenova.app.model.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.framenova.app.model.**$$serializer { *; }
