# telegraf-cluster

This repository provides a configuration pattern to run multiple **Telegraf** instances as a **high-availability (HA) cluster**.

The goal is to ensure that **only a single node per HA group actively publishes metrics**, while one or more standby nodes remain ready to take over in case of failure.

---

## Overview

By clustering multiple Telegraf instances, you can:

- Build **high availability** for metric collection
- Prevent duplicate metric ingestion
- Assign plugins to **HA groups** with automatic failover
- Avoid split-brain scenarios using quorum-based voting

The design is inspired by **Proxmox HA groups**.

---

## Key Concepts

### High Availability Groups
- Plugins can be assigned to an **HA group**
- Each HA group has:
  - One active **master**
  - One or more **backup** nodes

### Quorum & Split-Brain Prevention
- A quorum mechanism is used to elect a master
- At least **two connected instances** are required to elect a master
- This prevents split-brain conditions where multiple nodes believe they are master

---

## How It Works

### 1. Heartbeat Generation
- A **heartbeat metric** is generated using the `mock` input plugin

### 2. State Processing
- A **Starlark processor**:
  - Intercepts the heartbeat
  - Computes the local node state
  - Adds the node’s vote for each HA group to the heartbeat

### 3. Heartbeat Distribution
- The enriched heartbeat is sent to other nodes via the `influxdb_v2` output plugin

### 4. Heartbeat Reception
- Other nodes receive heartbeats using `influxdb_v2_listener`

### 5. Cluster State Management
- Received heartbeat data is stored in the processor’s internal state
- This state is used during the next local heartbeat evaluation

### 6. Metric Routing
- Once a master is elected:
  - Regular metrics are passed through the same processor
  - Metrics are **dropped or forwarded** based on:
    - The local node’s master/backup role
    - The HA group the metric belongs to

---

## Limitations / TODO

- [ ] Find a way to **enable or disable input plugins** dynamically based on HA group master state  
  (currently only output filtering is supported)

---

## Status

This configuration is functional and suitable for clustered Telegraf deployments, but still has room for improvement in dynamic plugin control.

---
