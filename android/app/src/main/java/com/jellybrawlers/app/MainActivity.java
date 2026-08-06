package com.jellybrawlers.app;

import android.app.Activity;
import android.opengl.GLSurfaceView;
import android.os.Bundle;
import android.view.MotionEvent;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

public class MainActivity extends Activity {

    private GLSurfaceView view;
    private long lastNano = 0L;

    private static native void nativeInit();
    private static native void nativeResize(int w, int h);
    private static native void nativeFrame(float dt);
    private static native void nativeTouch(int action, int id, float u, float v);

    static {
        System.loadLibrary("jelly");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        view = new GLSurfaceView(this);
        view.setEGLContextClientVersion(2);
        view.setPreserveEGLContextOnPause(true);
        view.setRenderer(new Renderer());
        view.setRenderMode(GLSurfaceView.RENDERMODE_CONTINUOUSLY);
        setContentView(view);
    }

    @Override
    protected void onResume() {
        super.onResume();
        view.onResume();
    }

    @Override
    protected void onPause() {
        super.onPause();
        view.onPause();
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        int actionMasked = e.getActionMasked();
        int w = view.getWidth();
        int h = view.getHeight();
        if (w == 0 || h == 0) return true;

        if (actionMasked == MotionEvent.ACTION_CANCEL) {
            for (int i = 0; i < e.getPointerCount(); ++i) {
                nativeTouch(1, e.getPointerId(i), 0, 0);
            }
            return true;
        }

        if (actionMasked == MotionEvent.ACTION_POINTER_DOWN ||
                actionMasked == MotionEvent.ACTION_DOWN) {
            int idx = e.getActionIndex();
            int id = e.getPointerId(idx);
            nativeTouch(0, id, e.getX(idx) / w, 1.0f - e.getY(idx) / h);
            return true;
        }

        if (actionMasked == MotionEvent.ACTION_POINTER_UP ||
                actionMasked == MotionEvent.ACTION_UP) {
            int idx = e.getActionIndex();
            int id = e.getPointerId(idx);
            nativeTouch(1, id, e.getX(idx) / w, 1.0f - e.getY(idx) / h);
            return true;
        }

        if (actionMasked == MotionEvent.ACTION_MOVE) {
            for (int i = 0; i < e.getPointerCount(); ++i) {
                int id = e.getPointerId(i);
                nativeTouch(2, id, e.getX(i) / w, 1.0f - e.getY(i) / h);
            }
            return true;
        }
        return true;
    }

    private class Renderer implements GLSurfaceView.Renderer {
        @Override
        public void onSurfaceCreated(GL10 gl, EGLConfig config) {
            nativeInit();
            lastNano = System.nanoTime();
        }

        @Override
        public void onSurfaceChanged(GL10 gl, int width, int height) {
            nativeResize(width, height);
        }

        @Override
        public void onDrawFrame(GL10 gl) {
            long now = System.nanoTime();
            float dt = (float) ((now - lastNano) / 1e9);
            lastNano = now;
            if (dt > 0.05f) dt = 0.05f;
            nativeFrame(dt);
        }
    }
}