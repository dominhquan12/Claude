# EDSN Integration — Summary

> Source: `edsn-api.docx` (qualification document, valid from 12-02-2025)
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

**Authentication**: mTLS with PKCS12 certificate + WS-Security (WSS4JSecurityHandler)

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

| Profile | `edsn.base-url` | Environment |
|---------|----------------|---------|
| `dev` / `testdev` | `https://portaal-act.edsn.nl` | ACT (acceptance) |
| `prod` | `https://portaal-opt.edsn.nl` | OPT (test/qualification) |
| P4 (both) | `https://pp4-test.edsn.nl/P4BatchVerzoekMeterstand/P4Port` | Test |

Keystore: `keystore-crawler.p12` (in classpath resources), password in config.

---

## 4. Endpoints — complete overview

All paths are relative to `edsn.base-url`.

### Synchronous operations (`/b2b/synchroon/`)

| Operation | Config key | Description |
|-----------|-----------|-------------|
| MoveIn | `move-in-url` | New customer on a connection |
| MoveInBatch | `move-in-batch-url` | Batch MoveIn |
| MoveOut | `move-out-url` | Customer leaves connection |
| MoveOutBatch | `move-out-batch-url` | Batch MoveOut |
| ChangeOfSupplier | `change-of-supplier-url` | Supplier switch |
| ChangeOfSupplierBatch | `change-of-supplier-batch-url` | Batch supplier switch |
| EndOfSupply | `end-of-supply-url` | End of supply |
| EndOfSupplyBatch | `end-of-supply-batch-url` | Batch end of supply |
| ChangeOfPV | `change-of-pv-url` | Change of balance responsible party |
| ChangeOfPVBatch | `change-of-pv-batch-url` | Batch ChangeOfPV |
| NameChange | `name-change-url` | Name change on connection |
| MasterData | `master-data-url` | Retrieve master data for EAN |
| MasterDataBatch | `master-data-batch-url` | Batch master data |
| MasterDataUpdate | `master-data-update-url` | Receive master data updates (pull) |
| GetMeteringPointMP | `get-metering-point-url` | Full metering point info per EAN |
| SearchMeteringPointsMP | `search-metering-points-url` | Search metering points |
| GetSCMPInformation | `get-scmp-information-url` | Retrieve SCMP information |
| NoticeEOS | `notice-eos-url` | End of supply notification |
| NoticeEOSNotification | `notice-eos-url` | Confirm incoming EOS notification |
| MeterReadingExchange | `meter-reading-url` | Exchange meter readings (pull) |
| MeterReadingExchangeNotification | `meter-reading-url` | Submit meter readings |
| RejectionMeterReading | `meter-reading-url` | Retrieve meter reading rejections |
| MeterReadingRejectionNotification | `meter-reading-url` | Confirm rejection |
| MeterReadingRejection | `meter-reading-url` | Submit rejection |

### Batch results (`/b2b/batch/`)

| Operation | Config key | Description |
|-----------|-----------|-------------|
| GainResult | `loss-gain-reject-update-url` | Retrieve gained connections |
| LossResult | `loss-gain-reject-update-url` | Retrieve lost connections |
| RejectionResult | `loss-gain-reject-update-url` | Retrieve rejections |
| UpdateResult | `loss-gain-reject-update-url` | Retrieve updates |

### P4 (meter reading batch)

| Operation | URL | Description |
|-----------|-----|-------------|
| P4CollectedDataBatchRequest | `edsn.p4-url` | Submit meter readings batch |
| P4CollectedDataBatchResultRequest | `edsn.p4-url` | Retrieve batch result |

---

## 5. Request/Response — all tested scenarios (from edsn-api.docx)

> Exact JSON from the qualification screenshots on OPT environment.

---

### 5.1 MoveIn

**URL:** `POST /api/moveIn`

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

**URL:** `POST /api/moveOut`

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

**URL:** `POST /api/changeOfSupplier`

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

**URL:** `POST /api/endOfSupply`

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

**URL:** `POST /api/changeOfPV`

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

**URL:** `POST /api/nameChange`

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

**URL:** `POST /api/getMeteringPoint`

**Request**
```json
{ "eanid": "112089200000000193" }
```

**Response (ELK — smart meter with 4 registers)**
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

**URL:** `POST /api/masterData`

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

**URL:** `POST /api/searchMeteringPoints`

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

**URL:** `POST /api/gainResult` · `POST /api/lossResult`

No request body — pull operation. EDSN returns a list of gained (Gain) or lost (Loss) connections.

**Response (GainResult example)**
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

**Response (LossResult — empty list)**
```json
{ "portaalMeteringPoint": [] }
```

---

### 5.11 MasterDataUpdate

**URL:** `POST /api/masterDataUpdate`

No request body — pull operation. Retrieves updates sent by the grid operator.

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

**URL:** `POST /api/meterReadingExchangeNotification`

Submit meter reading to EDSN (supplier pushes).

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
        "reading": {
          "reading": "600",
          "readingDate": "2025-02-12",
          "readingMethod": "22"
        }
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

**URL:** `POST /api/meterReadingExchange`

Retrieve meter readings from EDSN.

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

**URL:** `POST /api/getSCMPInformation`

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

**Response (GAS meter with complete master data)**
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

### 5.15 P4 — Submit batch meter readings

**URL:** `POST /api/p4`

Submit một lô yêu cầu đọc dữ liệu smart meter lên EDSN. EDSN xử lý bất đồng bộ — kết quả lấy qua `p4Result`.

**QueryReason codes:** `DAY` (Dagstand — đọc ngày), `INT` (Intervalstand — interval), `RCY` (maandstand recovery)

**Request**
```json
{
  "p4MeteringPoint": [
    {
      "eanid": "112089200000000193",
      "externalReference": "20250212001",
      "queryDate": "2025-02-12",
      "queryReason": "DAY"
    }
  ]
}
```

**Response (ACK — accepted)**
```json
{
  "p4Rejection": null
}
```

**Response (rejected)**
```json
{
  "p4Rejection": {
    "rejectionCode": "INVALID_EAN",
    "rejectionDescription": "EAN not found"
  }
}
```

---

### 5.16 P4Result — Retrieve batch meter reading results

**URL:** `POST /api/p4Result`

Poll để lấy kết quả của lô P4 đã submit. Trả về hourly records per register (OBIS code) per EAN. Không có request body.

**Request:** _(no body)_

**Response (ELK smart meter — 4 registers, rút gọn 3 giờ đại diện per register)**
```json
{
  "p4MeteringPoint": [
    {
      "eanid": "871687500000000001",
      "externalReference": "MOCK-871687500000000001",
      "queryDate": "2025-02-12",
      "queryReason": "DAY",
      "p4EnergyMeter": [
        {
          "p4Register": [
            {
              "id": "1-0:1.8.1",
              "measureUnit": "KWH",
              "p4Reading": [
                { "reading": 0.00, "readingDateTime": "2025-02-12T00:00:00.000+01:00" },
                { "reading": 0.45, "readingDateTime": "2025-02-12T07:00:00.000+01:00" },
                { "reading": 0.45, "readingDateTime": "2025-02-12T12:00:00.000+01:00" }
              ]
            },
            {
              "id": "1-0:1.8.2",
              "measureUnit": "KWH",
              "p4Reading": [
                { "reading": 0.12, "readingDateTime": "2025-02-12T00:00:00.000+01:00" },
                { "reading": 0.00, "readingDateTime": "2025-02-12T07:00:00.000+01:00" },
                { "reading": 0.00, "readingDateTime": "2025-02-12T12:00:00.000+01:00" }
              ]
            },
            {
              "id": "1-0:2.8.1",
              "measureUnit": "KWH",
              "p4Reading": [
                { "reading": 0.00, "readingDateTime": "2025-02-12T00:00:00.000+01:00" },
                { "reading": 0.00, "readingDateTime": "2025-02-12T07:00:00.000+01:00" },
                { "reading": 0.35, "readingDateTime": "2025-02-12T10:00:00.000+01:00" }
              ]
            },
            {
              "id": "1-0:2.8.2",
              "measureUnit": "KWH",
              "p4Reading": [
                { "reading": 0.00, "readingDateTime": "2025-02-12T00:00:00.000+01:00" },
                { "reading": 0.00, "readingDateTime": "2025-02-12T07:00:00.000+01:00" },
                { "reading": 0.00, "readingDateTime": "2025-02-12T12:00:00.000+01:00" }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

> Full response có 24 readings per register (24 giờ). Response trên rút gọn 3 giờ đại diện per register để dễ đọc.
>
> Register mapping: `1-0:1.8.1` = T1 piek consumption, `1-0:1.8.2` = T2 dal consumption, `1-0:2.8.1` = T3 piek production (solar), `1-0:2.8.2` = T4 dal production (solar).

---

### MutationReason codes

| Code | Operation |
|------|---------|
| `MOVEIN` | MoveIn |
| `MOVEOUT` | MoveOut |
| `SWITCHLV` | ChangeOfSupplier |
| `EOSUPPLY` | EndOfSupply |
| `SWITCHPV` | ChangeOfPV |
| `DSTRCONN` | MasterData (direct connection) |
| `PERMTR` | MeterReadingExchange (permanent meter reading) |

---

## 6. Test data (OPT environment)

| Field | Value |
|------|--------|
| Grid operator ID | `1120892404300` |
| Balance supplier (Crawler) | `8720892404305` |
| Balance responsible party | `7620299584017` |
| EAN GAS (test) | `112089200000000315` |
| EAN ELK (test) | `112089200000000254`, `112089200000000193`, `112089200000000278` |

---

## 7. Implementation status

| Component | Status |
|-----------|--------|
| WSDL generated classes | ✅ Present (generated in `target/`) |
| `EdsnService.java` | ✅ Fully implemented |
| `EdsnController.java` | ✅ Fully implemented |
| WS-Security / mTLS | ✅ `WSS4JSecurityHandler` + `TrustAllCertificates` |
| URL configuration (all environments) | ✅ Configured in `application-dev.yml` / `application-prod.yml` |
| Keystore file | ✅ `keystore-crawler.p12` in classpath |

**Conclusion**: EDSN integration is fully implemented. No missing components for basic functionality.

---

## 8. Relevant files

```
src/main/java/nl/crawler/custom/
├── controller/EdsnController.java          ← REST endpoints (30+ operations)
└── service/edsn/
    ├── EdsnService.java                    ← SOAP client implementation
    ├── WSS4JSecurityHandler.java           ← WS-Security handler
    ├── WSSecurityCrypto.java               ← Crypto configuration
    ├── TrustAllCertificates.java           ← SSL trust-all (test only)
    └── WSSecurityHandler.java              ← Alternative security handler

src/main/resources/
├── keystore-crawler.p12                    ← PKCS12 certificate
└── config/
    ├── application-dev.yml                 ← URLs: portaal-act.edsn.nl
    └── application-prod.yml                ← URLs: portaal-opt.edsn.nl

.claude/tasks/
├── edsn-api.docx                           ← Qualification document (original)
└── edsn-integration-summary.md             ← This file
```

---

## 9. Mock EDSN Gateway — Implementation Plan

> Reason: portaal-act.edsn.nl is unstable (sometimes works, sometimes not).
> Goal: stable local mock so business logic can be developed without network dependency.

### 9.1 Approach

**Strategy:** `MockEdsnService extends EdsnService` with `@Primary @Profile("mock")`.
Spring injects the mock into `EdsnController` (which declares `private final EdsnService edsnService`) — **zero code changes** in existing classes.

**Activate:**
```
--spring.profiles.active=dev,mock
```

**File to create:**
```
src/main/java/nl/crawler/custom/service/edsn/MockEdsnService.java
```

---

### 9.2 EAN strategy

EAN is already present in DB (retrieved via `ecbinfoset` API at contract creation).

- **Mutation methods** (`moveIn`, `moveOut`, `changeOfSupplier`, `endOfSupply`, `changeOfPV`, `nameChange`, batch variants): echo EAN from request back in response + auto-increment dossier ID.
- **`getMeteringPoint`**: inject `EanRepositoryCustom` → read `productType` from DB → build ELK (4 registers) or GAS (1 register) response. Fallback: ELK dual tariff.

---

### 9.3 Method coverage

| Method(s) | Mock response |
|---|---|
| `moveIn`, `moveOut`, `changeOfSupplier`, `endOfSupply`, `changeOfPV`, `nameChange` | Echo EAN + dossier ID (AtomicLong from `113656857`) + mutationReason per method |
| Batch variants (`moveInBatch`, ...) | Empty batch container |
| `getMeteringPoint` | DB lookup productType → ELK: 4 registers (1.8.1/1.8.2/2.8.1/2.8.2) or GAS: 1 register (1.8.2) |
| `masterData`, `masterDataBatch`, `masterDataUpdate` | Empty container (not yet in use) |
| `searchMeteringPoints` | Empty list |
| `getSCMPInformation` | Empty container |
| **Supplier switching** | |
| `gainResult` | 1 metering point: EAN from last call, mutationReason=SWITCHLV, dossier ID |
| `lossResult` | 1 metering point: EAN ELK test, mutationReason=SWITCHLV |
| `rejectionResult` | 1 rejection: rejectionCode=`EAN_ALREADY_IN_SWITCH` |
| `updateResult` | 1 update: status=CONFIRMED |
| **Meter reading** | |
| `meterReadingExchange` (pull) | ACK: `edsnsimpleRejection = null` |
| `meterReadingExchangeNotification` (push) | ACK: `edsnsimpleRejection = null` |
| `rejectionMeterReading`, `meterReadingRejectionNotification`, `meterReadingRejection` | Empty container |
| `p4` | ACK ACCEPTED |
| `p4Result` | 24 hourly records for EAN ELK (2025-02-12): hour 00–07 = T2 off-peak (~0.10 kWh/h), hour 07–23 = T1 peak (~0.45 kWh/h), hour 10–14 = T3 peak production (~0.35 kWh/h) |
| **EOS** | |
| `noticeEOS`, `noticeEOSNotification` | ACK / empty container |

---

### 9.4 Exception scenarios

**Trigger A — Magic EAN** (per call):

| EAN | Behavior |
|---|---|
| `000000000000000500` | Throws `WebServiceFaultException` (EDSN 500) |
| `000000000000000408` | Sleep 30s → `ResourceAccessException` (timeout) |
| `000000000000000422` | Throws `WebServiceFaultException` (EDSN rejection) |

**Trigger B — Global property** (all calls):

```yaml
# application-mock.yml
mock:
  edsn:
    scenario: happy   # happy | error-500 | timeout | reject
```

Each method first calls `applyScenario()` and `checkErrorTrigger(ean)` before the happy path.

---

### 9.5 Constants

```
GRID_OPERATOR_ID        = "1120892404300"
BALANCE_SUPPLIER_ID     = "8720892404305"
BRP_ID                  = "7620299584017"
MUTATION_DATE           = "2025-02-12"
DOSSIER_START           = 113656857L  (AtomicLong, auto-increment)
```
