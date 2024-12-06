# Box Visibility Analysis0
ThiS project implements a 3D visibility determination algorithm using PostgreSQL and PostGIS. The goal is to determine which **faces of 3D boxes** are visible from a given viewer position. The implementation leverages **recursive SQL queries** to calculate visibility based on geometric properties like distance and elevation angle.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Setup](#setup)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This repository demonstrates how to:

- Represent 3D boxes and their faces in a spatial database.
- Calculate visibility of box faces using **recursive SQL queries**.
- Handle geometric computations with **PostGIS** functions.

### Problem Statement

**Given:**
1. A set of 3D boxes, defined by their minimum and maximum corners (`x_min, y_min, z_min` and `x_max, y_max, z_max`).
2. A viewer position defined in 3D space (`x, y, z`).

![Example Image](/blendVis.png)

**Determine:**
- Which faces of each box are **visible** or **obstructed** when viewed from the given position.

---

## Features

- **Geometric Calculations**: Uses **PostGIS** to compute distances, angles, and intersections.
- **Recursive SQL**: Employs **recursive Common Table Expressions (CTEs)** for visibility determination.
- **Efficient Face Handling**: Processes faces in order of distance to eliminate redundant computations.

---

## Getting Started

### Prerequisites

1. **PostgreSQL** (version 12+ recommended).
2. **PostGIS Extension** installed in your PostgreSQL instance.

### Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/your-username/box-visibility-analysis.git
   cd box-visibility-analysis -- example run using: psql -U postgres -d vis_3D -f "C:\Users\Ingrid\sql_scripts\visuals3D.sql"
