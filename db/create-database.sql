create database easymeter;
CREATE TABLE `easymeter_data` (
  `createDate` datetime NOT NULL,
  `ownershipNumber` int(11) NOT NULL DEFAULT '0',
  `importCounter` decimal(20,4) DEFAULT NULL,
  `exportCounter` decimal(20,4) DEFAULT NULL,
  `powerL1` decimal(10,2) DEFAULT NULL,
  `powerL2` decimal(10,2) DEFAULT NULL,
  `powerL3` decimal(10,2) DEFAULT NULL,
  `powerOverall` decimal(10,2) DEFAULT NULL,
  `state` smallint(6) DEFAULT NULL,
  `serialNumber` char(15) COLLATE utf8_bin DEFAULT NULL,
  `consumption` decimal(10,2) DEFAULT NULL,
  `generation` decimal(10,2) DEFAULT NULL,
  `export` decimal(10,2) DEFAULT NULL,
  PRIMARY KEY (`ownershipNumber`,`createDate`),
  KEY `idx_easymeter_data_createDate` (`createDate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;