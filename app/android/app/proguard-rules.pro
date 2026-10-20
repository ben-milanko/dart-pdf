# ML Kit discovers these classes by name from AndroidManifest.xml and calls
# getDeclaredConstructor().newInstance(). AGP 9's strict R8 full mode no longer
# implicitly keeps the no-argument constructor when a class is kept. Without
# this rule CommonComponentRegistrar survives but its constructor does not:
# ML Kit initialization fails and every document scan throws before launch.
-keep,allowoptimization class com.google.mlkit.** implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
