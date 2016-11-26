# How to use measure_deviate.sh

#### Usage: measure_deviate.sh [-f <tone_frequency][-c <connector>[-l <tone_duration>][-h]
```
 -f tone frequency in Hz (10 - 20000), default: 2200
 -c connector type either din6 or hd15, default: hd15
 -l length of tone in seconds, default 30
 -d set debug flag for more verbose console output
 -h no arg, display this message
```
* Use should be able to run this without being root
  * Make sure you are in groups gpio & audio

```bash
groups
```

* If you need to add yourself to a group then as root
```bash
usermod -a -G audio <your_user_name>
usermod -a -G gpio <your_user_name>
```

* You will need to log back in to have groups take affect
```bash
su <your_user_name>
# now verify
groups
```

* The script doesn't bother to check for length of wave files so if
you decide to change the duration of the tone delete that tone file first.

### Debug notes ###

* If you want more excessive console output be sure to set the **-d**
flag on the command line.

* If PTT is working but you are not getting any audio:
  *  run __alsamixer__ and verify that **LOL Outp** and **LOR Outp** are
enabled.
    * **LOL Outp** and **LOR Outp** are enabled if you see 00 in a box directly above them.
    * Toggle enable by hitting the letter __m__