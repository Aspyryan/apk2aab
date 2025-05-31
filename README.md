Make folder with .apk file in it

Decompile apk with latest apk tool jar https://apktool.org/
java -jar ..\apktool_2.11.1.jar d driftyYTM.apk -o decompile_apk -f -s

Go into decompiled folder, and edit AndroidManifest.xml:
• Delete 'com.android.vending.derived.apk.id' meta data
• Add 2 permissions:
<uses-permission android:name="android.car.permission.CAR_UX_RESTRICTIONS_CONFIGURATION"/>
<uses-permission android:name="android.car.permission.CAR_DRIVING_STATE"/>
• Add distractionOptimized to all activities wanted
<meta-data android:name="distractionOptimized" android:value="true"/>
• Update version code if already uploaded to play store
• Make sure package name matches the play store console one

Compile the resources using latest apktool-aapt2 from github: https://github.com/DexPatcher/dexpatcher-repo/tree/master/m2/dexpatcher-repo/ibotpeaches/apktool/apktool-aapt2:
• Download latest version (same version of apktool)
• Extract the jar, go to windows and copy the aapt2.exe to the tools folder
• Run '..\aapt2.exe compile --dir decompile_apk\res -o res.zip'

Link resources and create new base.zip:
• Download android.jar from https://github.com/Sable/android-platforms/tree/master
• Run ..\aapt2.exe link --proto-format -o base.zip -I ..\android-33.jar --manifest .\decompile_apk\AndroidManifest.xml --min-sdk-version 31 --target-sdk-version {LATEST SDK VERSION} --version-code 1 --version-name 1.0 -R res.zip --auto-add-overlay
• Things to keep in mind!
○ For resource x is private => Go to the xml and make all @android references to @\*android => Return to previous step
○ If any other erros from resource not found, make sure to play around with the android.jar versions. This only worked for me with android-33.

Unzip base.zip
Copy AndroidManifest.xml to manifest/AndroidManifest.xml
Copy assets and lib folder from original decompile
Copy contents of unknown to root/_
Copy all .dex files to dex/_
Final base directory structure should resemble:
base/
├── assets/
├── dex/
├── lib/
├── manifest/
│ └── AndroidManifest.xml
├── res/
├── root/
│ └── (unknown files, kotlin folder)
└── resources.pb

Rezip all contents:
jar cMf base.zip manifest dex res root lib assets resources.pb
Bundle it all to an .aab file with bundle tool downloaded from: https://github.com/google/bundletool/releases
java -jar bundletool.jar build-bundle --modules=base.zip --output=unsigned.aab
Sign the app bundle
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore <path_to_your_keystore>.jks -storepass <keystore_password> -keypass <key_password> <your_app_name>.aab <your_key_alias>

PS D:\Projects\TestCompile\testapp> .\apk2aab.ps1 -ApkPath D:\Projects\TestCompile\testapp\driftyYTM.apk -ApktoolJarPath D:\Projects\TestCompile\apktool_2.11.1.jar -Aapt2ExePath D:\Projects\TestCompile\aapt2.exe -AndroidJarPath D:\Projects\TestCompile\android-33.jar -BundletoolJarPath D:\Projects\TestCompile\bundletool-all-1.18.1.jar -KeystorePath D:\Projects\TestCompile\my-release-key.keystore -KeyAlias alias_name
