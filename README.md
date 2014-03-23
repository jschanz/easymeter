easymeter
=========

Get power values from an Easymeter Q3D electric meter.

Install to /opt/ and configure some values in /opt/easymeter/etc/easymeter.cfg
variables should be self explaining ... script should run every minute to gather more accurate data (e.g. for csv export or upcomig mysql support)

install a cronjob to /etc/cron.d/

/etc/cron.d/easymeter
*/1 * * * * root sleep 30;/opt/easymeter/bin/easymeter.pl > /var/log/easymeter.log 2>&1

you can skip the "sleep 30" command if you don't use pvoutput-upload. if you use pvoutput-upload it's recommended, because otherwise there would be some problemes with smaspot, bluetooth and the sma inverters
 
upload to pvoutput is done every 5 minutes

# CHANGELOG
# 23.03.2014 	2.5.0 	calculate real consuption with import and export counter (incl. smaspot support)

