package com.example;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class HTMLViewerTest extends Activity {
	long time;

	public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WebView webview = new WebView(this);
        setContentView(webview);
        webview.setWebViewClient(new WebViewClient() {
			public void onPageFinished(WebView view, String url) {
				System.out.println((System.currentTimeMillis()- time)+"ms");
			}
        });
        time = System.currentTimeMillis();
        webview.loadUrl("http://demo.zama.gnn.co.jp/~miyabe/a.svg");
        
    }
}