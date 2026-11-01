# Project files are stored as JSON through kotlinx.serialization.
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class com.framenova.app.model.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.framenova.app.model.**$$serializer { *; }

# PreviewEngine.releaseTrackSelectors reaches these by name to work around a Media3 1.9 leak.
-keepclassmembers class androidx.media3.transformer.CompositionPlayer { *** playerHolders; }
-keepclassmembers class androidx.media3.transformer.CompositionPlayer$SequencePlayerHolder { *** trackSelector; *** player; }
-keepclassmembers class androidx.media3.transformer.CompositionTrackSelector { *** trackSelectorInternal; }
-keepclassmembers class androidx.media3.exoplayer.trackselection.DefaultTrackSelector { *** spatializer; }
-keepclassmembers class androidx.media3.exoplayer.trackselection.DefaultTrackSelector$SpatializerWrapperV32 { void release(); }
