# JDL Post-Generate Skill

## Goal

After running `jhipster jdl jdl.jdl`, two files must be updated manually for every newly generated entity:

1. `src/main/resources/META-INF/orm.xml` — register the JPA sequence generator
2. `src/main/resources/config/liquibase/changelog/00000000000001_custom_schema.xml` — create the DB sequence + reset changeset

This skill automates both steps.

---

## Steps

### 1. Detect new entities

Read `jdl.jdl` and extract all entity names declared with `entity EntityName {`.

Read `src/main/resources/META-INF/orm.xml` and collect all entity class names already registered (they appear as `<entity class="nl.crawler.domain.EntityName">`).

New entities = entities in jdl.jdl that do NOT appear in orm.xml.

If there are no new entities, report that and stop.

### 2. Derive names from entity name

For each new entity `EntityName`, derive:

- **Sequence name**: `sequence_generator_` + snake_case(EntityName)
  - Conversion: insert `_` before each uppercase letter that follows a lowercase letter or digit, then lowercase everything.
  - Examples: `Contact` → `sequence_generator_contact`, `CustomerAccount` → `sequence_generator_customer_account`, `GridOperatorCapacityTariff` → `sequence_generator_grid_operator_capacity_tariff`
- **Table name**: snake_case(EntityName) using the same conversion rule
  - Examples: `CustomerAccount` → `customer_account`, `GridOperator` → `grid_operator`

### 3. Add to orm.xml

Insert this block for each new entity **just before the closing `</entity-mappings>` tag**:

```xml
  <entity class="nl.crawler.domain.EntityName">
    <attributes>
      <id name="id">
        <generated-value strategy="SEQUENCE" generator="sequence_generator_entity_name"/>
        <sequence-generator name="sequence_generator_entity_name" sequence-name="sequence_generator_entity_name" allocation-size="1"/>
      </id>
    </attributes>
  </entity>
```

Replace `EntityName` with the actual class name and `sequence_generator_entity_name` with the derived sequence name.

### 4. Add to 00000000000001_custom_schema.xml

Insert two changeSets for each new entity **just before the closing `</databaseChangeLog>` tag**:

```xml
  <changeSet id="sequence_generator_entity_name" author="jhipster">
    <createSequence sequenceName="sequence_generator_entity_name" startValue="1" incrementBy="1"/>
  </changeSet>
  <changeSet id="sequence_generator_entity_name_reset" author="jhipster">
    <sql>
      SELECT setval('sequence_generator_entity_name', (SELECT MAX(id) FROM table_name) + 1, false);
    </sql>
  </changeSet>
```

Replace `sequence_generator_entity_name` with the derived sequence name and `table_name` with the derived table name.

---

## Conventions

- Sequence name = `sequence_generator_` + snake_case entity name (standard for all new entities)
- Table name = snake_case entity name (JHipster default mapping)
- `allocation-size="1"` always — matches existing entries
- `author="jhipster"` always — matches existing entries
- Preserve all existing content and formatting in both files; only append new blocks

---

## After editing

Print a summary table of what was added:

| Entity | Sequence name | Table name |
|--------|--------------|------------|
| ...    | ...          | ...        |

Remind the user to verify the derived table name matches the actual generated table name in the Liquibase migration files (e.g., `20XXXXXXXXX_added_entity_EntityName.xml`), since JHipster may use a different table name if one was explicitly specified in the JDL.
