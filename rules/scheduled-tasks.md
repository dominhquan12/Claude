---
description: Scheduled jobs, ShedLock distributed locking, and adding new background tasks
---

## Overview

Scheduled jobs use Spring `@Scheduled` with ShedLock for distributed locking across replicas so only one instance executes per tick.

- Config class: `SchedulerConfiguration.java` — enables `@EnableSchedulerLock`
- Jobs location: `/src/main/java/nl/crawler/custom/service/job/`
- Lock table: `shedlock` (created automatically by Liquibase)
- Lock manager: PostgreSQL-backed JDBC

## Pattern

```java
@Scheduled(cron = "0 0 3 * * *")
@SchedulerLock(name = "myJob", lockAtMostFor = "30m", lockAtLeastFor = "5m")
public void myJob() { ... }
```

- `lockAtMostFor` — maximum time the lock is held even if the node dies
- `lockAtLeastFor` — minimum hold time to prevent back-to-back executions on clock drift

In dev (single instance) the lock is acquired immediately. In production with multiple replicas only one instance executes.
