# Approle + Snowflake DB Reproduction

## Overview

This reproduction demonstrates how to use the Vault Approle authentication method to authenticate to a Snowflake database. This will be setup using private key authnetication to Snowflake which is required post November 2025. The snowflake configuration will use a static role which maps 1:1 with a Snowflake user. 

## Prerequisites

- Running Vault Cluster
- Snowflake database
- Snowflake user with enough privileges to create and manage database users


## TODO: 
- setup approle auth piece
- talk about integration with vault agent (or another means to auth to vault using approle)
- setup snowflake db config
- setup static role
- setup mock table in snowflake to test credentials and query the table using snowflake cli (just to wrap a bow on it all)




```
vault secrets enable database
```

```
vault write database/config/snowflake \
  plugin_name=snowflake-database-plugin \
  allowed_roles="*" \
  connection_url="snowflake://{{username}}:{{password}}@{{host}}/{{database}}?warehouse={{warehouse}}&role={{role}}" \
  ...
```

```

```