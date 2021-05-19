Exec sp_helpdbfixedrole

SELECT sp.state_desc, sp.permission_name, sp.class_desc, sp.major_id, sp.minor_id, e.name
  FROM sys.server_permissions AS sp
  JOIN sys.server_principals AS l ON sp.grantee_principal_id = l.principal_id
  LEFT JOIN sys.endpoints AS e ON sp.major_id = e.endpoint_id
WHERE l.name in ('public', CURRENT_USER)

SELECT sp.state_desc, sp.permission_name, SCHEMA_NAME(o.schema_id) AS 'Schema', o.*
  FROM sys.database_permissions sp
  LEFT JOIN sys.all_objects o ON sp.major_id = o.object_id
  JOIN sys.database_principals u ON sp.grantee_principal_id = u.principal_id
WHERE u.name in ('public', CURRENT_USER) AND o.name IS NOT NULL
ORDER BY o.name

SELECT DISTINCT rp.name,
                ObjectType = rp.type_desc,
                PermissionType = pm.class_desc,
                pm.permission_name,
                pm.state_desc,
                ObjectType = CASE
                               WHEN obj.type_desc IS NULL
                                     OR obj.type_desc = 'SYSTEM_TABLE' THEN
                               pm.class_desc
                               ELSE obj.type_desc
                             END,
                s.Name as SchemaName,
                [ObjectName] = Isnull(ss.name, Object_name(pm.major_id))
FROM   sys.database_principals rp
       INNER JOIN sys.database_permissions pm
               ON pm.grantee_principal_id = rp.principal_id
       LEFT JOIN sys.schemas ss
              ON pm.major_id = ss.schema_id
       LEFT JOIN sys.objects obj
              ON pm.[major_id] = obj.[object_id]
       LEFT JOIN sys.schemas s
              ON s.schema_id = obj.schema_id
WHERE  rp.type_desc = 'DATABASE_ROLE' -- AND pm.class_desc <> 'DATABASE'
And    rp.name in ('public', CURRENT_USER)
ORDER  BY rp.name,
          rp.type_desc,
          pm.class_desc

SELECT class_desc,*
FROM sys.server_permissions
WHERE grantor_principal_id = (
    SELECT principal_id
    FROM sys.server_principals
        WHERE NAME = N'appname_owner')

SELECT NAME, type_desc
FROM sys.server_principals
WHERE principal_id IN (
    SELECT grantee_principal_id
    FROM sys.server_permissions
        WHERE grantor_principal_id = (
            SELECT principal_id
            FROM sys.server_principals
            WHERE NAME = N'appname_owner'))

SELECT DP1.name AS DatabaseRoleName, IsNull(DP2.name, 'No members') AS DatabaseUserName
 FROM sys.database_role_members AS DRM
 RIGHT OUTER JOIN sys.database_principals AS DP1
   ON DRM.role_principal_id = DP1.principal_id
 LEFT OUTER JOIN sys.database_principals AS DP2
   ON DRM.member_principal_id = DP2.principal_id
WHERE DP1.type = 'R'
ORDER BY DP1.name;
