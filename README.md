easymeter
=========

Get power values from an Easymeter Q3D electric meter.
Tested with the following "IR-Optokopf für EasyMeter Zähler (USB)" on a Raspberry Pi.
http://shop.co-met.info/artikeldetails/kategorie/Smart-Metering/artikel/ir-optokopf-fuer-easymeter-zaehler-usb.html

Please note, that some Raspis have problems with USB2Serial-Converters. To avoid freezes, modify /boot/cmdline.txt

```
dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait smsc95xx.turbo_mode=N profile=2 loglevel=7 dwc_otg.microframe_schedule=1 dwc_otg.fiq_fix_enable=1  sdhci-bcm2708.sync_after_dma=0 sdhci-bcm2708.enable_llm=1 dwc_otg.lpm_enable=0 dwc_otg.speed=1
```

Install Package to /opt/ and configure some values in /opt/easymeter/etc/easymeter.cfg
Variables should be self explaining ... script should run every minute to gather more accurate data (e.g. for csv export or mysql archive).

install a cronjob to /etc/cron.d/

__/etc/cron.d/easymeter__
```bash
*/1 * * * * root sleep 10 && /opt/easymeter/bin/easymeter.pl > /var/log/easymeter.log 2>&1
```

you can skip the "sleep 30" command if you don't use pvoutput-upload. if you use pvoutput-upload it's recommended, because otherwise there would be some problemes with smaspot, bluetooth and the sma inverters.

upload to pvoutput is done every 5 minutes

OpenHAB
-------

OpenHAB integration is done by the OpenHAB REST API.

**easymeter.items**

```
Group		Easymeter	<sun>		(All)

Number easymeter_ownership		"Zählernummer" 						<selfEnergy> 	(Easymeter)
Number easymeter_L1 			"L1 [%.2f Wh]" 						<selfEnergy> 	(Easymeter)
Number easymeter_L2 			"L2 [%.2f Wh]" 						<selfEnergy> 	(Easymeter)
Number easymeter_L3 			"L3 [%.2f Wh]" 						<selfEnergy> 	(Easymeter)
Number easymeter_consumption 	"Verbrauch [%.2f Wh]"				<selfEnergy> 	(Easymeter)
Number easymeter_import			"Netzbezug [%.2f Wh]"				<selfEnergy> 	(Easymeter)
Number easymeter_generation 	"Erzeugung PV-Anlage [%.2f Wh]" 	<selfEnergy> 	(Easymeter)
Number easymeter_export 		"Einspeisung PV-Anlage [%.2f Wh]"	<selfEnergy> 	(Easymeter)
Number easymeter_counter_import	"Zählerstand Bezug [%.2f KWh]"		<selfEnergy>	(Easymeter)
Number easymeter_counter_export "Zählerstand Einspeisung [%.2f KWh]" <selfEnergy>  (Easymeter)
String easymeter_last_update "Letzte Aktualisierung [%s]"					<timer>			(Easymeter)
```
![Openhab Sitemap](https://raw.githubusercontent.com/jschanz/easymeter/master/image/openhab_easymeter.png)

> Written with [StackEdit](https://stackedit.io/).
