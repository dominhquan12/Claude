# EDSN Integration — Summary

> Source: `edsn-api.docx` (kwalificatie document, geldig vanaf 12-02-2025)
> Analysed: 2026-06-20

---

## 1. Architecture

```
Internal caller / Frontend
        │  REST/JSON
        ▼
EdsnController  (@RestController /api/*)
        │  Java method call
        ▼
EdsnService     (SOAP/JAX-WS via generated classes)
        │  SOAP + WS-Security (WSS4J) + mTLS (PKCS12)
        ▼
EDSN Portaal    (portaal-act.edsn.nl / portaal-opt.edsn.nl)
```

**Protocol**: SOAP/JAX-WS — classes generated from WSDL at build time into `nl.crawler.ws.client.generated.*`

**Authentication**: mTLS met PKCS12 certificate + WS-Security (WSS4JSecurityHandler)

---

## 2. Identifiers

| Field | Value |
|-------|-------|
| Sender (Crawler Energie GLN) | `8720892404305` |
| Receiver (EDSN GLN) | `8712423010208` |
| Source authority | `GLN` |
| Source contact type | `DDQ_O` |
| Destination authority | `EAN.UCC` |
| Destination contact type | `EDSN` |

SOAP header (auto-filled per call): `messageID` (random UUID) + `creationTimestamp` (now).

---

## 3. Environments & URLs

| Profile | `edsn.base-url` | Omgeving |
|---------|----------------|---------|
| `dev` / `testdev` | `https://portaal-act.edsn.nl` | ACT (acceptance) |
| `prod` | `https://portaal-opt.edsn.nl` | OPT (test/kwalificatie) |
| P4 (both) | `https://pp4-test.edsn.nl/P4BatchVerzoekMeterstand/P4Port` | Test |

Keystore: `keystore-crawler.p12` (in classpath resources), password in config.

---

## 4. Endpoints — volledig overzicht

Alle paths zijn relatief t.o.v. `edsn.base-url`.

### Synchrone operaties (`/b2b/synchroon/`)

| Operation | Config key | Beschrijving |
|-----------|-----------|-------------|
| MoveIn | `move-in-url` | Nieuwe klant op een aansluiting |
| MoveInBatch | `move-in-batch-url` | Batch MoveIn |
| MoveOut | `move-out-url` | Klant verlaat aansluiting |
| MoveOutBatch | `move-out-batch-url` | Batch MoveOut |
| ChangeOfSupplier | `change-of-supplier-url` | Leverancierswisseling |
| ChangeOfSupplierBatch | `change-of-supplier-batch-url` | Batch leverancierswisseling |
| EndOfSupply | `end-of-supply-url` | Einde levering |
| EndOfSupplyBatch | `end-of-supply-batch-url` | Batch einde levering |
| ChangeOfPV | `change-of-pv-url` | Wijziging programmaverantwoordelijke |
| ChangeOfPVBatch | `change-of-pv-batch-url` | Batch ChangeOfPV |
| NameChange | `name-change-url` | Naamswijziging op aansluiting |
| MasterData | `master-data-url` | Opvragen masterdata van EAN |
| MasterDataBatch | `master-data-batch-url` | Batch masterdata |
| MasterDataUpdate | `master-data-update-url` | Ontvangen masterdata updates (pull) |
| GetMeteringPointMP | `get-metering-point-url` | Volledige meteringpoint info per EAN |
| SearchMeteringPointsMP | `search-metering-points-url` | Zoek meteringpoints |
| GetSCMPInformation | `get-scmp-information-url` | SCMP informatie opvragen |
| NoticeEOS | `notice-eos-url` | Notificatie einde levering |
| NoticeEOSNotification | `notice-eos-url` | Inkomende EOS notificatie bevestigen |
| MeterReadingExchange | `meter-reading-url` | Meterstanden uitwisselen (pull) |
| MeterReadingExchangeNotification | `meter-reading-url` | Meterstanden insturen |
| RejectionMeterReading | `meter-reading-url` | Afwijzingen meterstanden ophalen |
| MeterReadingRejectionNotification | `meter-reading-url` | Afwijzing bevestigen |
| MeterReadingRejection | `meter-reading-url` | Afwijzing insturen |

### Batch resultaten (`/b2b/batch/`)

| Operation | Config key | Beschrijving |
|-----------|-----------|-------------|
| GainResult | `loss-gain-reject-update-url` | Gewonnen aansluitingen ophalen |
| LossResult | `loss-gain-reject-update-url` | Verloren aansluitingen ophalen |
| RejectionResult | `loss-gain-reject-update-url` | Afwijzingen ophalen |
| UpdateResult | `loss-gain-reject-update-url` | Updates ophalen |

### P4 (meterstand batch)

| Operation | URL | Beschrijving |
|-----------|-----|-------------|
| P4CollectedDataBatchRequest | `edsn.p4-url` | Meterstanden batch insturen |
| P4CollectedDataBatchResultRequest | `edsn.p4-url` | Resultaat batch ophalen |

---

## 5. Request/Response — alle geteste scenarios (uit edsn-api.docx)

> Exacte JSON uit de kwalificatie screenshots op OPT environment.

---

### 5.1 MoveIn

**Request**
```json
{
  "eanid": "112089200000000315",
  "gridOperatorCompany": { "id": "1120892404300" },
  "portaalMutation": {
    "externalReference": "12022025001",
    "mutationDate": "2025-02-12"
  },
  "mpcommercialCharacteristics": {
    "gridContractParty": { "surname": "kwalificatietest" },
    "balanceSupplierCompany": { "id": "8720892404305" },
    "balanceResponsiblePartyCompany": { "id": "7620299584017" }
  }
}
```

**Response**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000315",
    "productType": "GAS",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalMutation": {
      "externalReference": "12022025001",
      "mutationDate": "2025-02-12",
      "mutationReason": "MOVEIN",
      "dossier": { "id": "113656857" }
    },
    "mpcommercialCharacteristics": {
      "balanceSupplierCompany": { "id": "8720892404305" },
      "oldBalanceSupplierCompany": null,
      "balanceResponsiblePartyCompany": { "id": "7620299584017" }
    }
  },
  "portaalRejection": null
}
```

---

### 5.2 MoveOut

**Request**
```json
{
  "eanid": "112089200000000308",
  "gridOperatorCompany": { "id": "1120892404300" },
  "portaalMutation": {
    "externalReference": "12022025002",
    "mutationDate": "2025-02-13"
  },
  "mpcommercialCharacteristics": {
    "balanceSupplierCompany": { "id": "8720892404305" }
  }
}
```

**Response**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000308",
    "productType": "GAS",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalMutation": {
      "externalReference": "12022025002",
      "mutationDate": "2025-02-13",
      "mutationReason": "MOVEOUT",
      "dossier": { "id": "113656974" }
    },
    "mpcommercialCharacteristics": {
      "oldBalanceSupplierCompany": { "id": "8720892404305" }
    }
  },
  "portaalRejection": null
}
```

---

### 5.3 ChangeOfSupplier

**Request**
```json
{
  "eanid": "112089200000000254",
  "gridOperatorCompany": { "id": "1120892404300" },
  "portaalMutation": {
    "mutationDate": "2025-02-13"
  },
  "mpcommercialCharacteristics": {
    "balanceSupplierCompany": { "id": "8720892404305" },
    "balanceResponsiblePartyCompany": { "id": "7620299584017" }
  }
}
```

**Response**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000254",
    "productType": "ELK",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalMutation": {
      "externalReference": null,
      "mutationDate": "2025-02-13",
      "mutationReason": "SWITCHLV",
      "dossier": { "id": "113656981" }
    },
    "mpcommercialCharacteristics": {
      "balanceSupplierCompany": { "id": "8720892404305" },
      "oldBalanceSupplierCompany": { "id": "8720892404305" },
      "balanceResponsiblePartyCompany": { "id": "7620299584017" }
    }
  },
  "portaalRejection": null
}
```

---

### 5.4 EndOfSupply

**Request**
```json
{
  "eanid": "112089200000000278",
  "gridOperatorCompany": { "id": "1120892404300" },
  "portaalMutation": {
    "externalReference": "12022025003",
    "mutationDate": "2025-02-13"
  },
  "mpcommercialCharacteristics": {
    "balanceSupplierCompany": { "id": "8720892404305" }
  }
}
```

**Response**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000278",
    "productType": "ELK",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalMutation": {
      "externalReference": "12022025003",
      "mutationDate": "2025-02-13",
      "mutationReason": "EOSUPPLY",
      "dossier": { "id": "113656995" }
    },
    "mpcommercialCharacteristics": {
      "oldBalanceSupplierCompany": { "id": "8720892404305" }
    }
  },
  "portaalRejection": null
}
```

---

### 5.5 ChangeOfPV

**Request**
```json
{
  "eanid": "112089200000000193",
  "gridOperatorCompany": { "id": "1120892404300" },
  "portaalMutation": {
    "externalReference": "12022025004",
    "mutationDate": "2025-02-12"
  },
  "mpcommercialCharacteristics": {
    "balanceSupplierCompany": { "id": "8720892404305" },
    "balanceResponsiblePartyCompany": { "id": "7620299584017" }
  }
}
```

**Response**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000193",
    "productType": "ELK",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalMutation": {
      "externalReference": "12022025004",
      "mutationDate": "2025-02-12",
      "mutationReason": "SWITCHPV",
      "dossier": { "id": "113656996" }
    },
    "mpcommercialCharacteristics": {
      "balanceSupplierCompany": { "id": "8720892404305" },
      "balanceResponsiblePartyCompany": { "id": "7620299584017" }
    }
  },
  "portaalRejection": null
}
```

---

### 5.6 NameChange

**Request**
```json
{
  "eanid": "112089200000000254",
  "gridOperatorCompany": { "id": "1120892404300" },
  "portaalMutation": {
    "externalReference": "12022025005"
  },
  "mpcommercialCharacteristics": {
    "gridContractParty": {
      "initials": "C",
      "surname": "Kwalificatie",
      "surnamePrefix": "de"
    },
    "balanceSupplierCompany": { "id": "8720892404305" }
  }
}
```

**Response**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000254",
    "portaalMutation": {
      "dossier": { "id": "113657224" }
    },
    "mpcommercialCharacteristics": {
      "balanceSupplierCompany": { "id": "8720892404305" }
    }
  },
  "portaalRejection": null
}
```

---

### 5.7 GetMeteringPointMP

**Request**
```json
{ "eanid": "112089200000000193" }
```

**Response** (ELK — smart meter met 4 registers)
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000193",
    "administrativeStatusSmartMeter": "AAN",
    "gridArea": "1120892404300000004",
    "locationDescription": null,
    "marketSegment": "KVB",
    "productType": "ELK",
    "validFromDate": "2025-02-12",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalEnergyMeter": {
      "nrOfRegisters": null,
      "id": "312202401",
      "temperatureCorrection": null,
      "type": "SLM",
      "technicalCommunicationSM": "SMU",
      "register": [
        { "id": "1.8.1", "meteringDirection": "LVR", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null },
        { "id": "1.8.2", "meteringDirection": "LVR", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null },
        { "id": "2.8.1", "meteringDirection": "TLV", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null },
        { "id": "2.8.2", "meteringDirection": "TLV", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null }
      ]
    },
    "meteringPointGroup": null,
    "mpphysicalCharacteristics": {
      "allocationMethod": "PRF",
      "capTarCode": "87602271021117",
      "contractedCapacity": null,
      "energyDeliveryStatus": "ACT",
      "energyFlowDirection": "CMB",
      "invoiceMonth": null,
      "maxConsumption": null,
      "meteringMethod": "JRL",
      "physicalCapacity": null,
      "physicalStatus": "IBD",
      "profileCategory": "E1C",
      "appliance": null,
      "articleSub": null,
      "disconnectionMethod": null,
      "subtype": null,
      "sustainableEnergy": null,
      "switchability": null,
      "eaenergyConsumptionNettedOffPeak": 1500,
      "eaenergyConsumptionNettedPeak": 1651,
      "eaenergyProductionNettedOffPeak": 0,
      "eaenergyProductionNettedPeak": 0,
      "sderegulation": null
    },
    "mpcommercialCharacteristics": {
      "gridContractParty": [],
      "balanceSupplierCompany": { "id": "8720892404305" },
      "balanceResponsiblePartyCompany": { "id": "7620299584017" },
      "meteringResponsiblePartyCompany": null
    },
    "edsnaddressExtended": [{
      "bag": null,
      "streetName": "Parelduikerlaan",
      "buildingNr": 1,
      "exBuildingNr": null,
      "cityName": "ALMERE",
      "country": "NL",
      "zipcode": "1343CH",
      "tntid": null
    }],
    "edsngeographicalCoordinate": null
  },
  "portaalRejection": null
}
```

---

### 5.8 MasterData

**Request**
```json
{
  "eanid": "112089200000000193",
  "gridOperatorCompany": { "id": "1120892404300" },
  "portaalMutation": {
    "externalReference": "12022025011",
    "portaalUserInformation": { "organisation": "8720892404305" }
  }
}
```

**Response**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000193",
    "administrativeStatusSmartMeter": "AAN",
    "gridArea": "1120892404300000004",
    "marketSegment": "KVB",
    "productType": "ELK",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalEnergyMeter": {
      "id": "312202401",
      "type": "SLM",
      "technicalCommunicationSM": "SMU",
      "register": [
        { "id": "1.8.1", "meteringDirection": "LVR", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null },
        { "id": "1.8.2", "meteringDirection": "LVR", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null },
        { "id": "2.8.1", "meteringDirection": "TLV", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null },
        { "id": "2.8.2", "meteringDirection": "TLV", "multiplicationFactor": 1, "nrOfDigits": 6, "tariffType": null }
      ]
    },
    "portaalMutation": {
      "externalReference": "12022025011",
      "mutationReason": "DSTRCONN",
      "mutationDate": "2025-01-29",
      "dossier": { "id": "113659180" }
    },
    "mpphysicalCharacteristics": {
      "allocationMethod": "PRF",
      "capTarCode": "87602271021117",
      "energyDeliveryStatus": "ACT",
      "energyFlowDirection": "CMB",
      "meteringMethod": "JRL",
      "physicalStatus": "IBD",
      "profileCategory": "E1C",
      "eaenergyConsumptionNettedOffPeak": 1500,
      "eaenergyConsumptionNettedPeak": 1651,
      "eaenergyProductionNettedOffPeak": 0,
      "eaenergyProductionNettedPeak": 0
    },
    "mpcommercialCharacteristics": {
      "balanceSupplierCompany": { "id": "8720892404305" },
      "balanceResponsiblePartyCompany": { "id": "7620299584017" }
    },
    "edsnaddressSearch": {
      "bag": null,
      "streetName": "Parelduikerlaan",
      "buildingNr": 1,
      "cityName": "ALMERE",
      "country": "NL",
      "zipcode": "1343CH"
    }
  },
  "portaalRejection": null
}
```

---

### 5.9 SearchMeteringPointsMP

**Request**
```json
{ "eanid": "112029900000014234" }
```

**Response**
```json
{
  "result": {
    "reachedMaxResult": 1,
    "portaalMeteringPoint": [{
      "eanid": "112029900000014234",
      "gridArea": "112029958401800000",
      "locationDescription": null,
      "marketSegment": "KVB",
      "productType": "ELK",
      "gridOperatorCompany": { "id": "1120299584018", "name": "" },
      "portaalEnergyMeter": [{ "id": "2345" }],
      "meteringPointGroup": null,
      "mpphysicalCharacteristics": {
        "allocationMethod": null,
        "contractedCapacity": null,
        "energyFlowDirection": null,
        "invoiceMonth": null,
        "meteringMethod": null,
        "physicalCapacity": null,
        "profileCategory": null,
        "subtype": null
      },
      "edsnaddressSearch": {
        "bag": null,
        "streetName": "Raaphorstlaan",
        "buildingNr": 45,
        "exBuildingNr": null,
        "cityName": "'S-GRAVENHAGE",
        "country": "NL",
        "zipcode": "2532BG"
      }
    }]
  },
  "portaalRejection": null
}
```

---

### 5.10 GainResult / LossResult

Geen request body — pull operatie. EDSN geeft lijst terug van gewonnen (Gain) of verloren (Loss) aansluitingen.

**Response (GainResult voorbeeld)**
```json
{
  "portaalMeteringPoint": [{
    "eanid": "112089200000000254",
    "productType": "ELK",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalMutation": {
      "externalReference": null,
      "mutationDate": "2025-02-13",
      "mutationReason": "SWITCHLV",
      "dossier": { "id": "113656981" }
    },
    "mpcommercialCharacteristics": {
      "balanceSupplierCompany": { "id": "8720892404305" },
      "oldBalanceSupplierCompany": { "id": "8720892404305" },
      "balanceResponsiblePartyCompany": null,
      "oldBalanceResponsiblePartyCompany": null,
      "meteringResponsiblePartyCompany": null,
      "oldMeteringResponsiblePartyCompany": null
    }
  }]
}
```

**Response (LossResult — lege lijst)**
```json
{ "portaalMeteringPoint": [] }
```

---

### 5.11 MasterDataUpdate

Geen request body — pull operatie. Haalt updates op die grid operator heeft doorgestuurd.

**Response (GAS meter)**
```json
{
  "portaalMeteringPoint": [{
    "eanid": "112089200000000315",
    "productType": "GAS",
    "validFromDate": null,
    "validToDate": null,
    "portaalEnergyMeter": {
      "id": "G22071972",
      "nrOfRegisters": 0,
      "register": [{
        "measureUnit": "MTQ",
        "meteringDirection": null,
        "nrOfDigits": 5,
        "tariffType": null,
        "reading": null,
        "volume": {
          "calorificCorrectedVolume": "",
          "volume": "500",
          "reading": [
            { "reading": "0",   "readingDate": "2025-02-12", "readingMethod": "003" },
            { "reading": "500", "readingDate": "2025-02-12", "readingMethod": "003" }
          ]
        }
      }]
    },
    "portaalMutation": {
      "consumer": "8720892404305",
      "externalReference": "20250212001",
      "initiator": "1120892404300",
      "mutationReason": "PERMTR",
      "dossier": { "id": "113660047" }
    },
    "mpphysicalCharacteristics": {
      "capTarCode": "87602272011177",
      "energyFlowDirection": "LVR",
      "meteringMethod": "JRL",
      "physicalStatus": "IBD",
      "profileCategory": "G1A",
      "eaenergyConsumptionNettedPeak": 190
    },
    "edsnaddressSearch": {
      "streetName": "Spieringdam",
      "buildingNr": 2,
      "cityName": "'S-GRAVENHAGE",
      "country": "NL",
      "zipcode": "2492ND"
    }
  }],
  "portaalRejection": null
}
```

---

### 5.12 MeterReadingExchangeNotification

Meterstand insturen naar EDSN (supplier stuurt).

**Request**
```json
{
  "portaalMeteringPoint": [{
    "eanid": "112089200000000315",
    "portaalEnergyMeter": {
      "id": "G22071972",
      "nrOfRegisters": 0,
      "register": [{
        "measureUnit": "MTQ",
        "meteringDirection": "LVR",
        "nrOfDigits": 5,
        "reading": "600",
        "readingDate": "2025-02-12",
        "readingMethod": "22"
      }]
    }
  }],
  "portaalMutation": {
    "consumer": "1120892404300",
    "externalReference": "20250212001",
    "initiator": "8720892404305",
    "mutationReason": "PERMTR"
  }
}
```

**Response**
```json
{ "edsnsimpleRejection": null }
```

---

### 5.13 MeterReadingExchangeRequest (pull)

Meterstanden ophalen bij EDSN.

**Request**
```json
{
  "eanid": "112089200000000315",
  "portaalMutation": {
    "externalReference": "12022025009",
    "portaalUserInformation": { "organisation": "8720892404305" }
  }
}
```

**Response (GAS meter)**
```json
{
  "portaalMeteringPoint": [{
    "eanid": "112089200000000315",
    "productType": "GAS",
    "portaalEnergyMeter": {
      "id": "G22071972",
      "nrOfRegisters": 0,
      "register": [{
        "measureUnit": "MTQ",
        "meteringDirection": null,
        "nrOfDigits": 5,
        "tariffType": null,
        "reading": null,
        "volume": {
          "calorificCorrectedVolume": "",
          "volume": "500",
          "reading": [
            { "reading": "0",   "readingDate": "2025-02-12", "readingMethod": "003" },
            { "reading": "500", "readingDate": "2025-02-12", "readingMethod": "003" }
          ]
        }
      }]
    },
    "portaalMutation": {
      "consumer": "8720892404305",
      "externalReference": "20250212001",
      "initiator": "1120892404300",
      "mutationReason": "PERMTR",
      "dossier": { "id": "113660047" }
    }
  }]
}
```

---

### 5.14 GetSCMPInformation

**Request**
```json
{
  "eanid": "112089200000000315",
  "portaalMutation": {
    "externalReference": "12022025009",
    "portaalUserInformation": { "organisation": "8720892404305" }
  }
}
```

**Response (GAS meter met volledig masterdata)**
```json
{
  "portaalMeteringPoint": {
    "eanid": "112089200000000315",
    "administrativeStatusSmartMeter": "AAN",
    "gridArea": "1120892404300000011",
    "marketSegment": "KVB",
    "productType": "GAS",
    "gridOperatorCompany": { "id": "1120892404300" },
    "portaalEnergyMeter": {
      "id": "G22071972",
      "temperatureCorrection": "N",
      "type": "SLM",
      "technicalCommunicationSM": "SMU",
      "register": [
        { "id": "1.8.2", "meteringDirection": "LVR", "multiplicationFactor": 1, "nrOfDigits": 5, "tariffType": null }
      ]
    },
    "portaalMutation": {
      "externalReference": "12022025009",
      "mutationDate": "2025-02-12",
      "dossier": { "id": "113658863" }
    },
    "mpphysicalCharacteristics": {
      "capTarCode": "87602272011177",
      "energyFlowDirection": "LVR",
      "meteringMethod": "JRL",
      "physicalStatus": "IBD",
      "profileCategory": "G1A",
      "eaenergyConsumptionNettedPeak": 190
    },
    "mpcommercialCharacteristics": {
      "balanceSupplierCompany": { "id": "8720892404305" }
    },
    "edsnaddressSearch": {
      "streetName": "Spieringdam",
      "buildingNr": 2,
      "cityName": "'S-GRAVENHAGE",
      "country": "NL",
      "zipcode": "2492ND"
    }
  },
  "portaalRejection": null
}
```

---

### MutationReason codes

| Code | Operatie |
|------|---------|
| `MOVEIN` | MoveIn |
| `MOVEOUT` | MoveOut |
| `SWITCHLV` | ChangeOfSupplier |
| `EOSUPPLY` | EndOfSupply |
| `SWITCHPV` | ChangeOfPV |
| `DSTRCONN` | MasterData (directe verbinding) |
| `PERMTR` | MeterReadingExchange (permanente meterstand) |

---

## 6. Test data (OPT environment)

| Veld | Waarde |
|------|--------|
| Grid operator ID | `1120892404300` |
| Balance supplier (Crawler) | `8720892404305` |
| Balance responsible party | `7620299584017` |
| EAN GAS (test) | `112089200000000315` |
| EAN ELK (test) | `112089200000000254`, `112089200000000193`, `112089200000000278` |

---

## 7. Implementatiestatus

| Onderdeel | Status |
|-----------|--------|
| WSDL generated classes | ✅ Aanwezig (gegenereerd in `target/`) |
| `EdsnService.java` | ✅ Volledig geïmplementeerd |
| `EdsnController.java` | ✅ Volledig geïmplementeerd |
| WS-Security / mTLS | ✅ `WSS4JSecurityHandler` + `TrustAllCertificates` |
| URL configuratie (alle omgevingen) | ✅ Geconfigureerd in `application-dev.yml` / `application-prod.yml` |
| Keystore bestand | ✅ `keystore-crawler.p12` in classpath |

**Conclusie**: EDSN integratie is volledig geïmplementeerd. Geen ontbrekende onderdelen voor basisfunctionaliteit.

---

## 8. Relevante bestanden

```
src/main/java/nl/crawler/custom/
├── controller/EdsnController.java          ← REST endpoints (30+ operations)
└── service/edsn/
    ├── EdsnService.java                    ← SOAP client implementatie
    ├── WSS4JSecurityHandler.java           ← WS-Security handler
    ├── WSSecurityCrypto.java               ← Crypto configuratie
    ├── TrustAllCertificates.java           ← SSL trust-all (test only)
    └── WSSecurityHandler.java              ← Alternatieve security handler

src/main/resources/
├── keystore-crawler.p12                    ← PKCS12 certificate
└── config/
    ├── application-dev.yml                 ← URLs: portaal-act.edsn.nl
    └── application-prod.yml                ← URLs: portaal-opt.edsn.nl

.claude/tasks/
├── edsn-api.docx                           ← Kwalificatie document (origineel)
└── edsn-integration-summary.md             ← Dit bestand
```

---

## 9. Mock EDSN Gateway — Implementation Plan

> Reden: portaal-act.edsn.nl is instabiel (soms werkt het, soms niet).
> Doel: stabiele lokale mock zodat business logic ontwikkeld kan worden zonder netwerkafhankelijkheid.

### 9.1 Aanpak

**Strategie:** `MockEdsnService extends EdsnService` met `@Primary @Profile("mock")`.
Spring injecteert de mock in `EdsnController` (die `private final EdsnService edsnService` declareert) — **nul codewijzigingen** in bestaande klassen.

**Activeren:**
```
--spring.profiles.active=dev,mock
```

**Bestand aan te maken:**
```
src/main/java/nl/crawler/custom/service/edsn/MockEdsnService.java
```

---

### 9.2 EAN-strategie

EAN is al aanwezig in DB (opgehaald via `ecbinfoset` API bij contractaanmaak).

- **Mutation methods** (`moveIn`, `moveOut`, `changeOfSupplier`, `endOfSupply`, `changeOfPV`, `nameChange`, batch-varianten): echo EAN uit request terug in response + auto-increment dossier ID.
- **`getMeteringPoint`**: injecteer `EanRepositoryCustom` → lees `productType` uit DB → bouw ELK (4 registers) of GAS (1 register) response. Fallback: ELK dual tariff.

---

### 9.3 Method coverage

| Method(s) | Mock response |
|---|---|
| `moveIn`, `moveOut`, `changeOfSupplier`, `endOfSupply`, `changeOfPV`, `nameChange` | Echo EAN + dossier ID (AtomicLong vanaf `113656857`) + mutationReason per method |
| Batch-varianten (`moveInBatch`, ...) | Lege batch container |
| `getMeteringPoint` | DB lookup productType → ELK: 4 registers (1.8.1/1.8.2/2.8.1/2.8.2) of GAS: 1 register (1.8.2) |
| `masterData`, `masterDataBatch`, `masterDataUpdate` | Lege container (nog niet in gebruik) |
| `searchMeteringPoints` | Lege lijst |
| `getSCMPInformation` | Lege container |
| **Supplier switching** | |
| `gainResult` | 1 metering point: EAN uit last call, mutationReason=SWITCHLV, dossier ID |
| `lossResult` | 1 metering point: EAN ELK test, mutationReason=SWITCHLV |
| `rejectionResult` | 1 rejection: rejectionCode=`EAN_ALREADY_IN_SWITCH` |
| `updateResult` | 1 update: status=CONFIRMED |
| **Meter reading** | |
| `meterReadingExchange` (pull) | ACK: `edsnsimpleRejection = null` |
| `meterReadingExchangeNotification` (push) | ACK: `edsnsimpleRejection = null` |
| `rejectionMeterReading`, `meterReadingRejectionNotification`, `meterReadingRejection` | Lege container |
| `p4` | ACK ACCEPTED |
| `p4Result` | 24 hourly records voor EAN ELK (2025-02-12): uur 00–07 = T2 dal (~0.10 kWh/uur), uur 07–23 = T1 piek (~0.45 kWh/uur), uur 10–14 = T3 piek productie (~0.35 kWh/uur) |
| **EOS** | |
| `noticeEOS`, `noticeEOSNotification` | ACK / lege container |

---

### 9.4 Exception scenarios

**Trigger A — Magic EAN** (per call):

| EAN | Gedrag |
|---|---|
| `000000000000000500` | Gooit `WebServiceFaultException` (EDSN 500) |
| `000000000000000408` | Sleep 30s → `ResourceAccessException` (timeout) |
| `000000000000000422` | Gooit `WebServiceFaultException` (EDSN rejection) |

**Trigger B — Global property** (alle calls):

```yaml
# application-mock.yml
mock:
  edsn:
    scenario: happy   # happy | error-500 | timeout | reject
```

Elke method roept eerst `applyScenario()` en `checkErrorTrigger(ean)` aan vóór happy path.

---

### 9.5 Constanten

```
GRID_OPERATOR_ID        = "1120892404300"
BALANCE_SUPPLIER_ID     = "8720892404305"
BRP_ID                  = "7620299584017"
MUTATION_DATE           = "2025-02-12"
DOSSIER_START           = 113656857L  (AtomicLong, auto-increment)
```
