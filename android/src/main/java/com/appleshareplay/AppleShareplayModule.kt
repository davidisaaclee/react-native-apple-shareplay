// Android is not supported!
// I don't know what will happen if you compile this on Android. sorry!

package com.appleshareplay

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.annotations.ReactModule

@ReactModule(name = AppleShareplayModule.NAME)
class AppleShareplayModule(reactContext: ReactApplicationContext) :
  NativeAppleShareplaySpec(reactContext) {

  override fun getName(): String {
    return NAME
  }

  companion object {
    const val NAME = "AppleShareplay"
  }
}
