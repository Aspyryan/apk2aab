# APK2AAB With DistractionOptimized Changes
This repository has a script in it that will convert a .apk file and turn it into a .aab file with a couple of modifications to make driving while using the app possible.
Unlike the other apk2aab repositories, this repository actually has source code to look trough to ensure it's not a virus.

## Installation
Before running the script you will need a couple of tools:
| Tool Name | Description | Download Link | Version |
|-----------|-------------|---------------|---------|
| apktool.jar | Used to decompile the apk | [Official website](https://apktool.org/) | Latest version |
| aapt2.exe | Used to compile resources and link proto buff | [Dexpatcher apktool-aapt2 Repo](https://github.com/DexPatcher/dexpatcher-repo/tree/master/m2/dexpatcher-repo/ibotpeaches/apktool/apktool-aapt2) | Match version as above |
| bundletool.jar | Used to bundle everything back to aab file | [Google bundletool Repo](https://github.com/google/bundletool/releases) | Latest version |
| android.jar | Android jar of correct SDK version | [Sable Android Releases Repo](https://github.com/Sable/android-platforms/tree/master) | Play around with this |

NOTE: To get a aap2.exe file, you should extract the jar, go to windows and copy out the aapt2.exe file.

## Execution
To run this script. You should run following command:
`.\apk2aab.ps1 -ApkPath "app.apk" -ApktoolJarPath "apktool.jar" -Aapt2ExePath "aapt2.exe" -AndroidJarPath "android-33.jar" -BundletoolJarPath "bundletool.jar" -KeystorePath "keystore.jks" -KeyAlias "alias"`

## Description
This script will:
* Decompile the apk
* Modify the Android Manifest to make using the app while driving possible
* Compile the resources
* Link resources with manifest
* Create structure for .aab file
* Convert to .aab file
* Sign .aab

## Detail steps
Make sure the .apk file is in a empty directory, this will make the cleanup easier.

### Decompile APK
`java -jar apktool_2.11.1.jar d app.apk -o decompile_apk -f -s`

### Edit Android Manifest
Go into decompiled folder, and edit AndroidManifest.xml:
• Delete 'com.android.vending.derived.apk.id' meta data
• Add 2 permissions:
<uses-permission android:name="android.car.permission.CAR_UX_RESTRICTIONS_CONFIGURATION"/>
<uses-permission android:name="android.car.permission.CAR_DRIVING_STATE"/>
• Add distractionOptimized to all activities wanted
<meta-data android:name="distractionOptimized" android:value="true"/>
• Update package name to match parameter

### Compile resources
`aapt2.exe compile --dir decompile_apk\res -o res.zip'`

### Link resources
`aapt2.exe link --proto-format -o base.zip -I ..\android-33.jar --manifest .\decompile_apk\AndroidManifest.xml --min-sdk-version 31 --target-sdk-version {LATEST SDK VERSION} --version-code 1 --version-name 1.0 -R res.zip --auto-add-overlay`

The script will check if we get following error:
* For resource x is private => Go to the xml and make all `@android:` occurences equal `@\*android` => Return to previous step

If you get any other erros from resource not found, make sure to play around with the android.jar versions. This only worked for me with android-33.

### Create new bundle zip
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

### Zip contents
`jar cMf base.zip manifest dex res root lib assets resources.pb`

### Bundle to aab
`java -jar bundletool.jar build-bundle --modules=base.zip --output=unsigned.aab`

### Sign the bundle
`jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore <path_to_your_keystore>.jks -storepass <keystore_password> -keypass <key_password> <your_app_name>.aab <your_key_alias>`
