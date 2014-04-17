# create database
CREATE DATABASE `easymeter` DEFAULT CHARACTER SET utf8 COLLATE utf8_bin;

# create user -> change password and '%'
# eg. GRANT INSERT ON easymeter.easymeter_data TO easymeter@'10.1.1.15' IDENTIFIED BY 'topsecret';
GRANT INSERT ON easymeter.easymeter_data TO easymeter@'%' IDENTIFIED BY 'aic6viesah4Rutu0';

# create table
CREATE TABLE easymeter_data(
ownershipNumber int(11),
importCounter decimal (10,4), 
exportCounter decimal (10,4), 
powerL1 decimal (6,2), 
powerL2 decimal (6,2), 
powerL3 decimal (6,2), 
powerOverall decimal (6,2), 
state smallint, 
serialNumber char(15), 
consumption smallint, 
generation smallint, 
export smallint,
PRIMARY KEY (ownershipNumber)
)
ENGINE = INNODB;

