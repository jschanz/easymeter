#!/usr/bin/perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Copyright (C) 2013-2016 Jens Schanz
#
#
# Author:  Jens Schanz  <mail@jensschanz.de>
#
#
# 	0.1.0		->	first implementation
#	0.2.0		->	smaspot integration for power recalculation
#	0.2.1		->	calculation of consumption improved
#	0.2.2		->	peak consumption preserved for v10 parameter
#	0.2.3		->	smooth out invalid values of smaspot in combination with negativ consumption (delivery)
#	0.2.4		->	upload import register of easymeter as cumulative value (c1 = 1)
#	0.3.0		->	calculate acutal consumption and export by main import and export counters
#	2.5.0 		->	upgrade to new versioning schema ... refactoring of pvoutput upload function to get
#					more accurate consumption measurement
#	2.5.1  		->	bugfix in combination with sma inverters and etotal ... value wasn't written to history file
#	2.5.2		->	convert possible float values from easymeter import or export counter to simple int
#					add extended pvoutput values (v7, v8, v9, v10, v11)
#	2.5.3		->	float2int modified to sprintf (function int sometimes returns strange values), ntp drift improved
#	2.5.4		->	MySQL-Extension added -> see INSTALL
#	2.5.5		->	generation output bug in pvoutput fixed
#	2.6.0		->	Dashing-Extension (http://shopify.github.io/dashing/) added
#	2.6.1		->	date problem in pvoutput get for dashing fixed
#	2.6.2		->	dashing board description for total values fixed (W instead of W/h)
#	2.6.3		->	bugfix (issue #2) for negative etotal values if inverter doesn't respond
#	2.7.0		->	get values from easymeter by regex instead of splitting the return string
#	2.7.1		->	script supports now Q1D smartmeters
#	2.8.0		->	Graphite-Extension added
#	2.8.1		->	several bugs fixed
#	2.8.2		->	send data to openhab
# 	2.8.3		->	publish data to a mqtt server
# 	2.8.4		->	send data to influxdb
# 	2.8.5		->	send last update timestamp to http
#	2.8.6		->  auth for mqtt added
#	2.8.7		->  send mqtt values with mosquitto_pub instead of perl module
#	2.8.8		->  export real import values to mqtt and openhab to allow calculations based on that values
#
my $version = "2.8.8";
#
#

###
# create environment
use strict;
use warnings;

use POSIX;
use Device::SerialPort;

use File::Basename;

###
# define the environment we use
use FindBin qw($Bin);
my $basedir = $Bin;

###
# set up the log4perl environment
use Log::Log4perl qw(:easy);
Log::Log4perl->init($basedir . "/../etc/easymeter.conf");
my $logger = Log::Log4perl->get_logger();

###
# read config file
my %configOptions;
open( CONFIG, $basedir . "/../etc/easymeter.conf")
	or $logger->logdie ("Can't open ". $basedir . "/../etc/easymeter.conf");
while (<CONFIG>) {
	chomp;       												# new newline in file "\n"
	s/#.*//;     												# no comments
	s/^\s+//;    												# no leading whitespaces
	s/\s+$//;    												# no following whitespaces
	next unless length;    										# finished?
	my ( $var, $value ) = split( /\s*=\s*/, $_, 2 );
	$configOptions{$var} = $value;
}
close(CONFIG);

###
# map params from config file

# logger device
my $device = $configOptions{device};
my $device_baudrate = $configOptions{device_baudrate};
my $device_databits = $configOptions{device_databits};
my $device_stopbits = $configOptions{device_stopbits};
my $device_parity = $configOptions{device_parity};

# diff file
my $history_file = $configOptions{history_file};

# csv
my $csv = $configOptions{csv};
my $csv_file = $configOptions{csv_file};

# pvoutput
my $pvoutput_upload = $configOptions{pvoutput_upload};
my $pvoutput_apikey = $configOptions{pvoutput_apikey};
my $pvoutput_sid = $configOptions{pvoutput_sid};
my $pvoutput_temp_file = $configOptions{pvoutput_temp_file};

# smaspot
my $smaspot = $configOptions{smaspot};
my $smaspot_bin = $configOptions{smaspot_bin};

# stdout
my $stdout = $configOptions{stdout};

# MySQL
my $mysql = $configOptions{mysql};
my $mysql_user = $configOptions{mysql_user};
my $mysql_password = $configOptions{mysql_password};
my $mysql_server = $configOptions{mysql_server};
my $mysql_database = $configOptions{mysql_database};

# Dashing
my $dashing = $configOptions{dashing};
my $dashing_import_url = $configOptions{dashing_import_url};
my $dashing_export_url = $configOptions{dashing_export_url};
my $dashing_generation_url = $configOptions{dashing_generation_url};
my $dashing_consumption_url = $configOptions{dashing_consumption_url};

# OpenHAB
my $openhab = $configOptions{openhab};
my $openhab_ownership = $configOptions{openhab_ownership};
my $openhab_l1 = $configOptions{openhab_l1};
my $openhab_l2 = $configOptions{openhab_l2};
my $openhab_l3 = $configOptions{openhab_l3};
my $openhab_consumption = $configOptions{openhab_consumption};
my $openhab_import = $configOptions{openhab_import};
my $openhab_import_actual = $configOptions{openhab_import_actual};
my $openhab_generation = $configOptions{openhab_generation};
my $openhab_export = $configOptions{openhab_export};
my $openhab_last_update = $configOptions{openhab_last_update};
my $openhab_counter_import = $configOptions{openhab_counter_import};
my $openhab_counter_export = $configOptions{openhab_counter_export};

# Graphite
my $graphite = $configOptions{graphite};
my $carbon_server = $configOptions{carbon_server};
my $carbon_port = $configOptions{carbon_port};

# influxdb
my $influxdb = $configOptions{influxdb};
my $influxdb_host = $configOptions{influxdb_host};
my $influxdb_port = $configOptions{influxdb_port};
my $influxdb_user = $configOptions{influxdb_user};
my $influxdb_password = $configOptions{influxdb_password};
my $influxdb_ssl = $configOptions{influxdb_ssl};
my $influxdb_database = $configOptions{influxdb_database};
my $influxdb_measurement = $configOptions{influxdb_measurement};
my $influxdb_location = $configOptions{influxdb_location};

# MQTT
my $mqtt = $configOptions{mqtt};
my $mqtt_server = $configOptions{mqtt_server};
my $mqtt_user = $configOptions{mqtt_user};
my $mqtt_password = $configOptions{mqtt_password};
my $mqtt_topic = $configOptions{mqtt_topic};

###
# initalize serial device
# set serial interface
my $port = Device::SerialPort->new("$device");
$port->baudrate($device_baudrate);
$port->databits($device_databits);
$port->stopbits($device_stopbits);
$port->parity("$device_parity");
$port->read_const_time(1000);
$port->stty_istrip;
$port->read_char_time(0);
$port->write_settings || undef $port;

#############################################################################
# start with main here ...
#############################################################################

# read from device
$logger->info("######## easymeter.pl ($version) ########");
$logger->info("start reading from device");
my $rawData = readDevice();
if ($rawData) {
	# parse and transform raw data and create readable format
	$logger->debug("processing data: $rawData");
	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber) = parseRawData($rawData);

	# process history data and calculate imported and exported power between this and the last run
	my ($consumption, $generation, $export) = processHistoryData($importCounter, $exportCounter);

	###
	# possible output engines

	# create csv entry as comma seperated value
	if ($csv == 1) {
		$logger->info("CSV-Export is enable -> creating csv entry in $csv_file");
		processDataCSV($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("CSV-Export finished");
	}

	# upload data to pvoutput
	if ($pvoutput_upload == 1) {
		$logger->info("PVOutput-Export is enabled -> exporting data to pvoutput");
		processDataPvOutput($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("PVOutput-Export finished")
	}

	# store data in a MySQL database
	if ($mysql == 1) {
		$logger->info("MySQL-Export enabled -> storing data in database");
		processDataMySQL($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("MySQL-Export finished")
	}

	# export data to a dashing dashboard
	if ($dashing == 1) {
		$logger->info("Dashing-Export enabled -> refresh dashboard widgets");
		processDataDashing($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("Dashing-Export finished")
	}

	# export data to a dashing dashboard
	if ($openhab == 1) {
		$logger->info("openHAB-Export enabled -> update openHAB items");
		processDataOpenHAB($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("openHAB-Export finished")
	}

	# export data to graphite
	if ($graphite == 1) {
		$logger->info("Graphite-Export enabled -> send metrics to carbon-cache");
		processDataGraphite($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("Graphite-Export finished")
	}

	if ($mqtt == 1) {
		$logger->info("MQTT-Export enabled -> send values to MQTT-Server");
		processDataMqtt($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("MQTT-Export finished")
	}

	# export data to influxdb
	if ($influxdb == 1) {
		$logger->info("InfluxDB-Export enabled -> send values to API");
		processDataInfluxDB($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export);
		$logger->info("InfluxDB-Export finished")
	}

	# print to STDOUT
	if ($stdout == 1) {
		$logger->info("STDOUT enabled");
		print "$ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption\n";
	}
}
$logger->info("all done");
# all done
exit 0;

#############################################################################
# start with subs here
############################################################################

sub readDevice {
	my $retry = 10;

	while ($retry > 0) {
		# read the complete telegram block of 293 bytes
		my ($count,$rawData)=$port->read(293);
		# if data received process it
	    if ($count > 0) {
	    	# if data starts with /ESY
	    	if ($rawData =~ m/^\/ESY(.*)/) {
	    		# telegram starts with /ESY and is complete
	    		$logger->debug("valid data received: $rawData");
	    		return $rawData;
    		}
	 	} else {
	 		# if telegram is incomplete, try again, because read event starts often in the middle of a telegram
	 		if ($retry != 10) {
	 			$logger->warn("no valid data from logger received: $rawData");
	 		}
			--$retry;
		}
	}
}

sub parseRawData {
	my $rawData = $_[0];
	# parse data
	my @parameter = split /\r\n/, $rawData;
	# Eigentumsnummer (1-0:0.0.0*255)
	$parameter[2] = transformData($parameter[2]);
	my $ownerNumber = $rawData;
	if ($ownerNumber =~ m/1-0:0\.0\.0.*\((.*)\)/){
		$ownerNumber = $1;
	} else {
		$logger->error("OwnerNumber: error decoding received data, exiting.");
		exit;
	}
	

	# Bezugsregister (1-0:1.8.0*255) - kWh
	$parameter[3] = transformData($parameter[3]);
	$parameter[3] = convertkWh2Wh($parameter[3]);
	my $importCounter = $rawData;
	if ($importCounter =~ m/1-0:1\.8\.0.*\((.*)\*kWh\)/){
		$importCounter = convertkWh2Wh($1);
	} else {
		$logger->error("ImportCounter: error decoding received data, exiting.");
		exit;
	}

	# Lieferregister (1-0:2.8.0*255) - kWh
	$parameter[4] = transformData($parameter[4]);
	$parameter[4] = convertkWh2Wh($parameter[4]);
	my $exportCounter = $rawData;
	if ($exportCounter =~ m/1-0:2\.8\.0.*\((.*)\*kWh\)/) {
		$exportCounter = convertkWh2Wh($1);
	} else {
		$logger->error("ExportCounter: error decoding received data, exiting.");
		exit;
	}

	# Momentanleistung L1 (1-0:21.7.0*255) - Wh
	$parameter[5] = transformData($parameter[5]);
	$parameter[5] = $parameter[5]*1;
	my $powerL1 = $rawData;
	if ($powerL1 =~ m/1-0:21\.7\.0.*\((.*)\*W\)/) {
		$powerL1 = $1;
	} else {
		$logger->error("L1: error decoding received data, exiting.");
		exit;
	}

	# Momentanleistung L2 (1-0:41.7.0*255) - Wh
	$parameter[6] = transformData($parameter[6]);
	my $powerL2 = $rawData;
	if ($powerL2 =~ m/1-0:41\.7\.0.*\((.*)\*W\)/) {
		$powerL2 = $1;
	} else {
		$logger->error("L2: error decoding received data, exiting.");
		exit;
	}

	# Momentanleistung L3 (1-0:61.7.0*255) - Wh
	$parameter[7] = transformData($parameter[7]);
	my $powerL3 = $rawData;
	if ($powerL3 =~ m/1-0:61\.7\.0.*\((.*)\*W\)/) {
		$powerL3 = $1;
	} else {
		$logger->error("L3: error decoding received data, exiting.");
		exit;
	}

	# Momentanleistung L1+L2+L3 (1-0:1.7.0*255) - Wh
	$parameter[8] = transformData($parameter[8]);
	my $powerL1L2L3 = $rawData;
	if ($powerL1L2L3 =~ m/1-0:1\.7\.0.*\((.*)\*W\)/){
		$powerL1L2L3 = $1;
	} else {
		$logger->error("L1L2L3: error decoding received data, exiting.");
		exit;
	}
	

	# Statusinformation (1-0:96.5.5*255)
	# TODO: show bit status
	$parameter[9] = transformData($parameter[9]);
	my $status = $rawData;
	if ($status =~ m/1-0:96\.5\.5.*\((.*)\)/){
		$status = $1;
	} else {
		$logger->error("Statusinfo: error decoding received data, exiting.");
		exit;
	}
	

	# Fabriknummer (0-0:96.1.255*255)
	$parameter[10] = transformData($parameter[10]);
	my $serial = $rawData;
	if ($serial =~ m/0-0:96\.1\.255.*\((.*)/){
		$serial = $1;
	} else {
		$logger->error("Serial: error decoding received data, exiting.");
		exit;
	}
	

	# $logger->info("rawData old -> $parameter[2], $parameter[3], $parameter[4], $parameter[5], $parameter[6], $parameter[7], $parameter[8], $parameter[9], $parameter[10]");
	$logger->info("rawData new -> $ownerNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerL1L2L3, $status, $serial");
	return ($ownerNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerL1L2L3, $status, $serial);
	# return ($parameter[2], $parameter[3], $parameter[4], $parameter[5], $parameter[6], $parameter[7], $parameter[8], $parameter[9], $parameter[10]);
};

sub processDataCSV {

	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;

	my $datetime = `date +%d.%m.%y\\;%H:%M`;
	chomp($datetime);

	# open filehandle for writing
	open (FILEHANDLE, ">>$csv_file") or
		$logger->logdie("Could not create $csv_file");

	# write csv stream to filehandle
	print FILEHANDLE "$datetime;$ownershipNumber;$importCounter;$exportCounter;$powerL1;$powerL2;$powerL3;$powerOverall;$state;$serialNumber;$consumption;$generation;$export\n";

	# close filehandle
	close(FILEHANDLE);
}

sub processHistoryData {

	my $importCounter = float2int($_[0]);	# convert to int to avoid problems with possible float values
	my $exportCounter = float2int($_[1]);	# convert to int to avoid problems with possible float values
	my $epochSeconds = getEpochSeconds();

	# if pvoutput is enabled, read actual etotal
	my $etotal;
	if ($pvoutput_upload == 1) {
				$etotal = getSMAspotETotal();

	} else {
		$etotal = 0;
	}

	# read history values
	my ($historyImportCounter, $historyExportCounter, $historyEpochSeconds, $historyEtotal) = getHistoryCounter();
	$logger->info("$historyImportCounter, $historyExportCounter, $historyEpochSeconds, $historyEtotal");
	if (!$historyImportCounter) {
		$historyImportCounter = $importCounter;		# no valid value found
		$logger->warn("no valid history value found for import counter");
	}
	if (!$historyExportCounter) {
		$historyExportCounter = $exportCounter;		# no valid value found
		$logger->warn("no valid history value found for export counter");
	}
	if (!$historyEtotal) {
		$historyEtotal = $etotal;					# na valid value found
		$logger->warn("no valid history value found for ETotal");
	}

	# fix ntp drifting
	if ($epochSeconds < $historyEpochSeconds) {
		$epochSeconds = $historyEpochSeconds + 1;
	}

	# store actual values for next run
	setHistoryCounter($importCounter, $exportCounter, $epochSeconds, $etotal);

	#  calculate difference
	my $importDifference = $importCounter - $historyImportCounter;
	$logger->info("import: difference: $importDifference -> Counter: $importCounter -> history: $historyImportCounter");
	my $exportDifference = $exportCounter - $historyExportCounter;
	$logger->info("export: difference: $exportDifference -> Counter: $exportCounter -> history: $historyExportCounter");
	my $epochSecondsDifference = $epochSeconds - $historyEpochSeconds;
	$logger->info("time: difference: $epochSecondsDifference -> Seconds: $epochSeconds -> history: $historyEpochSeconds");

	if ($historyEtotal > $etotal) {
		$logger->warn("got $etotal as ETotal from inverter, but got $historyEtotal as history ETotal.");
		$logger->warn("setting ETotal to historical ETotal to avoid negative values");
		$etotal = $historyEtotal;

	}
	my $etotalDifference = $etotal - $historyEtotal;
	$logger->info("etotal: difference: $etotalDifference -> ETotal: $etotal -> history: $historyEtotal");

	my $epochSecondsAsHour = $epochSecondsDifference / 3600;

	# calculate consumption as average w/h
	# consumption = ((smaspot_etotal - easymeter_export) + easymeter_import) / secondsdifference * 3600
	# difference is calculated in seconds ... so do some math to get w/h
	# 1h = 60 min * 60 seconds = 3600 seconds
	my $consumption = ($etotalDifference - $exportDifference) + $importDifference;
	$consumption = $consumption / $epochSecondsAsHour;
	$logger->info("average consumption of $consumption Wh in the last $epochSecondsDifference seconds");

	# calculate generation as average w/h
	# generation = $etotalDifference / $epochSecondsAsHour
	my $generation = $etotalDifference / $epochSecondsAsHour;
	$logger->info("average generation of $generation Wh in the last $epochSecondsDifference seconds");

	# calculate export as average w/h
	# export = $exportDifference / $epochSecondsAsHour
	my $export = $exportDifference / $epochSecondsAsHour;
	$logger->info("average export of $export Wh in the last $epochSecondsDifference seconds");

	return ($consumption, $generation, $export);
}

sub getHistoryCounter {

	open my $filehandle, '<', $history_file or
		$logger->logwarn("Could not open $history_file");
	my $storedData = <$filehandle>;
	chomp($storedData);
	close($filehandle);

	my @history = split (/;/, $storedData);

	my $importCounter = $history[0];
	my $exportCounter = $history[1];
	my $epochSeconds = $history[2];
	my $etotal = $history[3];

	return ($importCounter, $exportCounter, $epochSeconds, $etotal);
}

sub setHistoryCounter {

	my ($importCounter, $exportCounter, $epochSeconds, $etotal) = @_;

	# write new data to file
	# open filehandle for writing
	open (FILEHANDLE, ">$history_file") or
		$logger->logdie("Could not create $history_file");

	# write new values to history file
	print FILEHANDLE "$importCounter;$exportCounter;$epochSeconds;$etotal";

	# close filehandle
	close(FILEHANDLE);
}

sub processDataPvOutput {

	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;

	# get timestamp
	my $date = `date +%Y%m%d`;
	chomp($date);
	my $time = `date +%H:%M`;
	chomp($time);

	# read stored history values
	open my $filehandle, '<', $pvoutput_temp_file or
		$logger->logdie("Could not open $pvoutput_temp_file");
	my $storedData = <$filehandle>;
	chomp($storedData);
	close($filehandle);

	# process stored history values
	# uploadcounter;1min;2min;3min;4min
	# if value is zero, set it to actual power
	my @history = split (/;/, $storedData);
	my $uploadcounter 	= $history[0];
	my $consumption1min = $history[1];
	my $consumption2min = $history[2];
	my $consumption3min = $history[3];
	my $consumption4min = $history[4];

	# if nothing is set (e.g. first run) preload variables with actual consumption to avoid wrong values
	if (($consumption1min ==  0) or (!$consumption1min)) {
		$logger->warn("no valid consumption from 1 minute ago found -> setting it to actual consumption");
		$consumption1min = $consumption;
	}
	if (($consumption2min ==  0) or (!$consumption2min)) {
		$logger->warn("no valid consumption from 2 minutes ago found -> setting it to actual consumption");
		$consumption2min = $consumption;
	}
	if (($consumption3min ==  0) or (!$consumption3min)) {
		$logger->warn("no valid consumption from 3 minutes ago found -> setting it to actual consumption");
		$consumption3min = $consumption;
	}
	if (($consumption4min ==  0) or (!$consumption4min)) {
		$logger->warn("no valid consumption from 4 minutes ago found -> setting it to actual consumption");
		$consumption4min = $consumption;
	}

	# calculate average consumption for the last 5 minutes to upload it to pvoutput
	# because only one upload in 5 minutes counts and is valid
	my $averageConsumption5min = ($consumption + $consumption1min + $consumption2min + $consumption3min + $consumption4min) / 5;
	$logger->info("average: $averageConsumption5min / actual: $consumption / 1min: $consumption1min / 2min: $consumption2min / 3min: $consumption3min / 4min: $consumption4min");

	# upload average consumption for the last 5 minutes
	# do this only every 5 minutes due to an upload limitation of pvoutput
	$logger->info("upload counter: ($uploadcounter / 5)");
	if ($uploadcounter == 1) {
		$logger->info("uploading average consumption of $averageConsumption5min to pvoutput");

		# modify $generation to show export in pvoutput extended tab
		$generation = $generation;

		# curl
		# -d "d=20111201"
		# -d "t=10:00"
		# -d "v1=1000"
		# -d "v2=150"
		# -H "X-Pvoutput-Apikey: e57001e6c79a2212ad9f879b35c1a4e75a797639"
		# -H "X-Pvoutput-SystemId: 23592"
		# http://pvoutput.org/service/r2/addstatus.jsp
		my @args = ("curl",
					"-d \"d=$date\"",
					"-d \"t=$time\"",
					"-d \"v4=$averageConsumption5min\"",
					"-d \"v7=$powerL1\"",
					"-d \"v8=$powerL2\"",
					"-d \"v9=$powerL3\"",
					"-d \"v10=$averageConsumption5min\"",
					"-d \"v11=$generation\"",
					"-H \"X-Pvoutput-Apikey: $pvoutput_apikey\"",
					"-H \"X-Pvoutput-SystemId: $pvoutput_sid\"",
					"http://pvoutput.org/service/r2/addstatus.jsp"
					);
		system("@args");

	}

	# increase upload counter
	if ($uploadcounter == 5) {
		$uploadcounter = 1;
	} else {
		++$uploadcounter;
	}

	# write new data to file
	# open filehandle for writing
	open (FILEHANDLE, ">$pvoutput_temp_file") or
		$logger->logdie("Could not create $pvoutput_temp_file");

	# write new values to history file
	print FILEHANDLE "$uploadcounter;$consumption;$consumption1min;$consumption2min;$consumption3min";

	# close filehandle
	close(FILEHANDLE);
}

sub processDataMySQL {

	use DBI;
	use DBD::mysql;

	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;

	# create database connection
	my $dbh = DBI->connect( "dbi:mysql:database=$mysql_database;host=$mysql_server",
					$mysql_user, $mysql_password, { AutoCommit => 0 } );
	$logger->warn ("Can not establish connection to $mysql_server->$mysql_database: $DBI::errstr")
	  unless defined $dbh;
	$logger->info("Connection to source: $mysql_server->$mysql_database established ...");
	my $createDate = `date +"%Y-%m-%d %H:%M:%S"`;

	my $sql = "INSERT INTO easymeter_data
					VALUES (
							'$createDate',
							'$ownershipNumber',
							'$importCounter',
							'$exportCounter',
							'$powerL1',
							'$powerL2',
							'$powerL3',
							'$powerOverall',
							'$state',
							'$serialNumber',
							'$consumption',
							'$generation',
							'$export')";
	$logger->debug($sql);

	my $sth = $dbh->prepare($sql) or
		$logger->warn( "error at prepare ..." . $dbh->errstr . "");
	$sth->execute() or
		$logger->warn( "error at execute ..." . $dbh->errstr . "");
	$sth->finish;

	# disconnect from database
	$dbh->commit;
	$dbh->disconnect();
}

sub processDataGraphite {
	use IO::Socket::INET;

	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;

	# create socket to communicate with carbon-cache
	my $socket = IO::Socket::INET->new (
			PeerAddr => $carbon_server,
			PeerPort => $carbon_port,
			Proto => 'tcp',
		);
	if (!$socket) {
		$logger->error("Unable to connect to carbon server!");
	}

	# get millisecs
	my $date = getMillisecs();

	# send data
	$socket->send("easymeter.importCounter $importCounter $date\n");
	$socket->send("easymeter.exportCounter $exportCounter $date\n");
	$socket->send("easymeter.L1 $powerL1 $date\n");
	$socket->send("easymeter.L2 $powerL2 $date\n");
	$socket->send("easymeter.L3 $powerL3 $date\n");
	$socket->send("easymeter.powerOverall $powerOverall $date\n");
	$socket->send("easymeter.consumption $consumption $date\n");
	$socket->send("easymeter.generation $generation $date\n");
	$socket->send("easymeter.export $export $date\n");

	$socket->shutdown(1);
}


sub processDataDashing {
	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;

	# treat powerOverall as import value (positive values only - negative values will be displayed in export widget)
	if ( $powerOverall < 0 ) {
		$powerOverall = 0;
	}

	use LWP::UserAgent;

	my $ua = LWP::UserAgent->new;

	# round values to avoid sizing problems in dashing
 	$powerOverall = sprintf("%.1f", $powerOverall);
 	$export = sprintf("%.1f", $export);
 	$generation = sprintf("%.1f", $generation);
 	$consumption = sprintf("%.1f", $consumption);

	my $date = getDate();

	# if pvoutput is enabled gather some statistics
	if ($pvoutput_upload == 1) {
		# curl  -d "c=1" -d "df=20140418" -d "dt=20140418" -H "X-Pvoutput-Apikey: 12345" -H "X-Pvoutput-SystemId: 23592" http://pvoutput.org/service/r2/getstatistic.jsp
		# 5937,925,5937,5937,5937,0.900,1,20140418,20140418,0.900,20140418,13003,7991,0,0,0,13003,13003,13003
		# Generated [1] (5937) / Exported [2] (925) /  Consumed [12] (13003) / Import [13] (7991)

		my $url = "curl -s -d \"c=1\" -d \"df=$date\" -d \"dt=$date\" -H \"X-Pvoutput-Apikey: $pvoutput_apikey\" -H \"X-Pvoutput-SystemId: $pvoutput_sid\" http://pvoutput.org/service/r2/getstatistic.jsp";
		my $pvoutput_statistics = `$url`;
		my @pvoutput_statistics_values = split(/,/,$pvoutput_statistics);

		$powerOverall = "$powerOverall W/h ($pvoutput_statistics_values[12] W)";
		$export = "$export W/h ($pvoutput_statistics_values[1] W)";
		$generation = "$generation W/h ($pvoutput_statistics_values[0] W)";
		$consumption = "$consumption W/h ($pvoutput_statistics_values[11] W)";
	}

	# build endpoint hash
	my %endpoint = (
        $dashing_import_url => $powerOverall,
        $dashing_export_url => $export,
        $dashing_generation_url => $generation,
        $dashing_consumption_url => $consumption
    );

	# export values to each endpoint
 	while ( my ($endpoint_url, $value) = each(%endpoint) ) {

 		$logger->info("$endpoint_url -> $value");

		# set custom HTTP request header fields
		my $req = HTTP::Request->new(POST => $endpoint_url);
		$req->header('content-type' => 'application/json');
		$req->header('x-auth-token' => 'YOUR_AUTH_TOKEN');

		# add POST data to HTTP request body
		my $post_data = '{ "auth_token": "YOUR_AUTH_TOKEN", "text": "' .  $value . '" }';
		$req->content($post_data);

		my $resp = $ua->request($req);
		if ($resp->is_success) {
	    	my $message = $resp->decoded_content;
	    	$logger->debug("Received reply: $message");
		} else {
	    	$logger->error("HTTP POST error code: $resp->code, ");
	    	$logger->error("HTTP POST error message: $resp->message ");
		}
    }
}

sub processDataOpenHAB {
	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;

	# get import value from powerOverall only if powerOverall > 0
	my $importActual = 0;
	if ( $powerOverall >= 0 ) {
		$importActual = $powerOverall;
	}

	use LWP::UserAgent;

	my $ua = LWP::UserAgent->new;

	# round values to avoid formatting in openhab
 	$powerOverall = sprintf("%.1f", $powerOverall);
 	$export = sprintf("%.1f", $export);
 	$generation = sprintf("%.1f", $generation);
 	$consumption = sprintf("%.1f", $consumption);

	$importCounter = convertWh2KWh($importCounter);
	$exportCounter = convertWh2KWh($exportCounter);

	my $date = getDate();
	my $datetime = `date "+%d.%m.%y %H:%M:%S"`;
	chomp($datetime);

	# build endpoint hash
	my %endpoint = (
		$openhab_ownership => $ownershipNumber,
		$openhab_counter_import => $importCounter,
		$openhab_counter_export => $exportCounter,
		$openhab_l1 => $powerL1,
		$openhab_l2 => $powerL2,
		$openhab_l3 => $powerL3,
		$openhab_consumption => $consumption,
		$openhab_import => $powerOverall,
		$openhab_import_actual => $importActual,
		$openhab_generation => $generation,
		$openhab_export => $export,
		$openhab_last_update => $datetime
  );

    # export values to each endpoint
    # curl -s -X PUT -H "Content-Type: text/plain" -d "100" "http://openhab:8080/rest/items/easymeter_L1/state"
 		while ( my ($endpoint_url, $value) = each(%endpoint) ) {

 		$logger->debug("$endpoint_url -> $value");

		# set custom HTTP request header fields
		my $req = HTTP::Request->new(PUT => $endpoint_url);
		$req->header('content-type' => 'text/plain');
		# $req->header('x-auth-token' => 'YOUR_AUTH_TOKEN');

		# add POST data to HTTP request body
		my $post_data = $value ;
		$req->content($post_data);

		my $resp = $ua->request($req);
		if ($resp->is_success) {
	    	my $message = $resp->decoded_content;
			if ($message) {
				$logger->debug("Received reply: $message");
			}
		} else {
	    	$logger->error("HTTP POST error code: $resp->code, ");
	    	$logger->error("HTTP POST error message: $resp->message ");
		}
	}
}

sub processDataMqtt {
	# http://search.cpan.org/~juerd/Net-MQTT-Simple/
	use Net::MQTT::Simple;

	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;
	
	# send ownership number
	sendDataMqtt('ownershipNumber', $ownershipNumber);

	# send kw/h instead of w/h
	$importCounter = $importCounter / 1000;
	sendDataMqtt('importCounter', $importCounter);

	# send kw/h instead of w/h
	$exportCounter = $exportCounter / 1000;
	sendDataMqtt('exportCounter', $exportCounter);

	# send L1, L2, L3
	sendDataMqtt('powerL1', $powerL1);
	sendDataMqtt('powerL2', $powerL2);
	sendDataMqtt('powerL3', $powerL3);
	sendDataMqtt('powerOverall', $powerOverall);

	# get import value from powerOverall only if powerOverall > 0
	my $importActual = 0;
	if ( $powerOverall >= 0 ) {
		$importActual = $powerOverall;
	}
	sendDataMqtt('import', $importActual);

	sendDataMqtt('state', $state);

	sendDataMqtt('serialNumber', $serialNumber);

	sendDataMqtt('consumption', $consumption);

	sendDataMqtt('generation', $generation);

	sendDataMqtt('export', $export);

	my $lastUpdate = `date +%s`;
	chomp($lastUpdate);
	sendDataMqtt('lastUpdate', $lastUpdate);

	if ($pvoutput_upload == 1) {
		my $consumptionToday = getConsumptionFromPvOutput();

		sendDataMqtt('consumptionToday', $consumptionToday);
	}
}

sub sendDataMqtt {
	my ($topic, $value) = @_;

	# connection string for mqtt
	my $mqtt_connection = "-h $mqtt_server -u $mqtt_user -P $mqtt_password";

	my $mqtt_connection_topic = "-t $mqtt_topic/$topic"; 
	my $mqtt_connection_message = "-m \"$value\"";
	my $mqtt_command = "mosquitto_pub " . $mqtt_connection . " " . $mqtt_connection_topic . " " . $mqtt_connection_message;
	system($mqtt_command);
}

sub processDataInfluxDB {
	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber, $consumption, $generation, $export) = @_;

	# treat powerOverall as import value (positive values only - negative values will be displayed in export widget)
	if ( $powerOverall < 0 ) {
		$powerOverall = 0;
	}
	my $timestamp = `date +%s`;
	chomp($timestamp);
	$timestamp = $timestamp * 1000000000;

	# use curl and line protocol, because several cpan modules are not working stable or doesn't
	# support the new line protocol
	system("curl -i -XPOST 'http://$influxdb_host:$influxdb_port/write?db=$influxdb_database' --data-binary '
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=importCounter value=$importCounter $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=exportCounter value=$exportCounter $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=powerL1 value=$powerL1 $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=powerL2 value=$powerL2 $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=powerL3 value=$powerL3 $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=powerOverall value=$powerOverall $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=consumption value=$consumption $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=generation value=$generation $timestamp \n
		easymeter,location=$influxdb_location,ownershipNumber=$ownershipNumber,key=export value=$export $timestamp
	' >/dev/null 2>&1");
}


sub transformData {
	my $data = $_[0];

	# transform 1-0:0.0.0*255(113940381) to
	# key: $1 = 1-0:0.0.0*255
	# value: $2 = 113940381

	# set $data to value
	$data =~ s/^(.*)\((.*)\)/$2/g;
	$data =~ s/\*kWh//g;
	$data =~ s/\*W//g;

	return $data;
}

sub convertkWh2Wh {
	my $data = $_[0];

	$data = $data * 1000;

	return $data;
}

sub convertWh2KWh {
	my $data = $_[0];

	$data = $data / 1000;

	return $data;
}

sub getEpochSeconds {

	my $epochSeconds = `date +%s`;
	chomp($epochSeconds);

	return $epochSeconds;
}

sub getDate {

	my $date = `date +%Y%m%d`;
	chomp ($date);

	return $date;
}

sub getMillisecs {

	my $date = `date +%s`;
	chomp ($date);

	return $date;
}

sub getSMAspotETotal {

	my $power = 0;
	my $attempt = 0;

	while ($power == 0) {
		++$attempt;
		# get ETotal from SMA inverter
		$power = `$smaspot_bin -v -finq -mqtt | grep \"ETotal\" | awk -F \":\" \'{ print \$2 }\' | sed \"s/kWh//g\" | sed \"s/ //g\"`;
		chomp($power);

		$logger->debug("received $power kWh from SmaSpot");

		# transform kWh in Wh
		$power = $power * 1000;

		$logger->info("received $power Wh from SmaSpot (attempt: $attempt)");

		# if inverter doesn't return a valid value, use history of etotal
		if ($attempt == 3) {
			my ($historyImportCounter, $historyExportCounter, $historyEpochSeconds, $historyEtotal) = getHistoryCounter();
			$power = $historyEtotal;
		}
	}

	return $power;
}

sub float2int {

	my $float = $_[0];

	my $int = sprintf("%.0f", $float);

	return $int;
}

sub getConsumptionFromPvOutput {
		my $date = getDate();

		my $url = "curl -s -d \"c=1\" -d \"df=$date\" -d \"dt=$date\" -H \"X-Pvoutput-Apikey: $pvoutput_apikey\" -H \"X-Pvoutput-SystemId: $pvoutput_sid\" http://pvoutput.org/service/r2/getstatistic.jsp";
		my $pvoutput_statistics = `$url`;
		my @pvoutput_statistics_values = split(/,/,$pvoutput_statistics);

		my $consumption = "$pvoutput_statistics_values[11]";
		return $consumption;
	}
