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
# Copyright (C) 2013 Jens Schanz
#
#
# Author:  Jens Schanz  <mail@jensschanz.de>
#
#
# 	0.1.0		->	first implementation
#	0.2.0		->	smaspot integration for power recalculation
#	0.2.1		->	calculation of consumption improved
#	0.2.2		->	peak consumption preserved for v10 parameter
#
my $version = "0.2.2";
#
#

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

###
# initilaize serial device
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
	# process data
	$logger->debug("processing data: $rawData");
	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber) = parseRawData($rawData);

	# create csv entry
	if ($csv == 1) {
		$logger->info("create csv entry in $csv_file");
		processDataCSV($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber);
	}
	
	# upload data to pvoutput
	if ($pvoutput_upload == 1) {
		$logger->info("pvoutput enabled");
		processDataPvOutput($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber);
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
		
	# Bezugsregister (1-0:1.8.0*255) - kWh
	$parameter[3] = transformData($parameter[3]);
	$parameter[3] = convertkWh2Wh($parameter[3]);
		
	# Lieferregister (1-0:2.8.0*255) - kWh
	$parameter[4] = transformData($parameter[4]);
	$parameter[4] = convertkWh2Wh($parameter[4]);
		
	# Momentanleistung L1 (1-0:21.7.0*255) - Wh
	$parameter[5] = transformData($parameter[5]);
	$parameter[5] = $parameter[5]*1;
		
	# Momentanleistung L2 (1-0:41.7.0*255) - Wh
	$parameter[6] = transformData($parameter[6]);
		
	# Momentanleistung L3 (1-0:61.7.0*255) - Wh
	$parameter[7] = transformData($parameter[7]);
		
	# Momentanleistung L1+L2+L3 (1-0:1.7.0*255) - Wh
	$parameter[8] = transformData($parameter[8]);
		
	# Statusinformation (1-0:96.5.5*255)
	# TODO: show bit status
	$parameter[9] = transformData($parameter[9]);
		
	# Fabriknummer (0-0:96.1.255*255)
	$parameter[10] = transformData($parameter[10]);
	
	$logger->debug("rawData -> $parameter[2], $parameter[3], $parameter[4], $parameter[5], $parameter[6], $parameter[7], $parameter[8], $parameter[9], $parameter[10]");
	return ($parameter[2], $parameter[3], $parameter[4], $parameter[5], $parameter[6], $parameter[7], $parameter[8], $parameter[9], $parameter[10]);
};

sub processDataCSV {
	
	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber) = @_;
	
	my $datetime = `date +%d.%m.%y\\;%H:%M`;
	chomp($datetime);
	
	# open filehandle for writing
	open (FILEHANDLE, ">>$csv_file") or
		$logger->logdie("Could not create $csv_file");

	# write csv stream to filehandle
	print FILEHANDLE "$datetime;$ownershipNumber;$importCounter;$exportCounter;$powerL1;$powerL2;$powerL3;$powerOverall;$state;$serialNumber\n";
		
	# close filehandle
	close(FILEHANDLE);
}

sub processDataPvOutput {
	
	my ($ownershipNumber, $importCounter, $exportCounter, $powerL1, $powerL2, $powerL3, $powerOverall, $state, $serialNumber) = @_;
	
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
	# timer;1min;2min;3min;4min;5min
	# if value is zero, set it to actual power
	my @history = split (/;/, $storedData);
	if ($history[1] ==  0) {
		$history[1] = $powerOverall; 	
	}
	if ($history[2] ==  0) {
		$history[2] = $powerOverall; 	
	}
	if ($history[3] ==  0) {
		$history[3] = $powerOverall; 	
	}
	if ($history[4] ==  0) {
		$history[4] = $powerOverall; 	
	}
	
	# preserve avtual power -> map actual power consumption to peak consumption.
	my $peakConsumptionPowerOverall = $powerOverall;
	
	# if smaspot is enabled, calculate "real" powerOverall
	my $smapower = 0;
	if ($smaspot == 1) {
		# smaspot enabled ... recalculate power data with smaspot values
		$logger->debug("smaspot enabled");
		$smapower = getSMAspotData();
		
		# recalculate (consumption + generation) 
		$logger->info("actual consumption (easymeter): $powerOverall / sma energy generation: $smapower");
		$powerOverall = $powerOverall + $smapower;
	}
		
	# to avoid high load spikes and lost outputs, calculate average load for the last 5 minutes
	my $avgPowerOverall = ($history[1] + $history[2] + $history[3] + $history[4] + $powerOverall) / 5;
	$logger->info("consumption -> now: $powerOverall / 1min: $history[1] / 2min: $history[2] / 3min: $history[3] / 4min: $history[4]");
	$logger->info("consumption -> average 5min: $avgPowerOverall / run: $history[0]");
		
	if ($history[0] == 1){
		# upload value to pvoutput
		$logger->debug("uploading actual power to pvoutput");
		
		# due to a limitation of pvoutput avoid negativ values
		if ($avgPowerOverall < 0) {
			$logger->warn("zero value found $avgPowerOverall -> please check, should never occur");
			$avgPowerOverall = 0;
		}
	
		$logger->info("uploading a average consumption of $avgPowerOverall (v4), a current consumption peak of $peakConsumptionPowerOverall (v10) and a generation of $smapower (v11)");
		
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
					"-d \"v4=$avgPowerOverall\"",
					"-d \"v7=$powerL1\"",
					"-d \"v8=$powerL2\"",
					"-d \"v9=$powerL3\"",
					"-d \"v10=$powerOverall\"",
					"-d \"v11=$smapower\"",
					"-H \"X-Pvoutput-Apikey: $pvoutput_apikey\"",
					"-H \"X-Pvoutput-SystemId: $pvoutput_sid\"",
					"http://pvoutput.org/service/r2/addstatus.jsp"
					);
		system("@args");
	}
		
	# increase counter (upload only every 5th value to pvoutput due to limitation of pvoutput)
	if ($history[0] == 5) {
		$history[0] = 1;
	} else {
		++$history[0];
	}
		
	# write new data to file
	# open filehandle for writing
	open (FILEHANDLE, ">$pvoutput_temp_file") or
		$logger->logdie("Could not create $pvoutput_temp_file");

	# write new values to history file
	print FILEHANDLE "$history[0];$powerOverall;$history[1];$history[2];$history[3];$history[4]";
		
	# close filehandle
	close(FILEHANDLE);
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

sub getSMAspotData {
	
	my $power = `$smaspot_bin -v -finq | grep \"Total Pac\" | awk -F \":\" \'{ print \$2 }\' | sed \"s/kW//g\" | sed \"s/ //g\"`;
	chomp($power);
	
	$logger->debug("received $power kW from SmaSpot");

	$power = $power * 1000;
	
	return $power;
}
