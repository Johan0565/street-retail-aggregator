package com.example.frontend; // Твой пакет

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import com.yandex.mapkit.MapKitFactory;

public class MainActivity extends FlutterActivity {
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        // Ключ обязательно должен передаваться ДО вызова super
        MapKitFactory.setApiKey("1cdf3269-ddc3-4fc5-9f3b-40550c256370");
        super.configureFlutterEngine(flutterEngine);
    }
}