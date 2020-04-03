-- Query generated by:
-- templates/clients_daily_scalar_aggregates.sql.py --agg-type keyed_booleans
WITH filtered AS (
  SELECT
    *,
    SPLIT(application.version, '.')[OFFSET(0)] AS app_version,
    DATE(submission_timestamp) AS submission_date,
    normalized_os AS os,
    application.build_id AS app_build_id,
    normalized_channel AS channel
  FROM
    `moz-fx-data-shared-prod.telemetry_stable.main_v4`
  WHERE
    DATE(submission_timestamp) = @submission_date
    AND normalized_channel IN ("release", "beta", "nightly")
    AND client_id IS NOT NULL
),
grouped_metrics AS (
  SELECT
    sample_id,
    client_id,
    submission_date,
    os,
    app_version,
    app_build_id,
    channel,
    ARRAY<STRUCT<name STRING, process STRING, value ARRAY<STRUCT<key STRING, value BOOLEAN>>>>[
      ('a11y_theme', 'parent', payload.processes.parent.keyed_scalars.a11y_theme),
      (
        'devtools_tool_registered',
        'parent',
        payload.processes.parent.keyed_scalars.devtools_tool_registered
      ),
      ('sandbox_no_job', 'parent', payload.processes.parent.keyed_scalars.sandbox_no_job),
      (
        'security_pkcs11_modules_loaded',
        'parent',
        payload.processes.parent.keyed_scalars.security_pkcs11_modules_loaded
      ),
      (
        'services_sync_sync_login_state_transitions',
        'parent',
        payload.processes.parent.keyed_scalars.services_sync_sync_login_state_transitions
      ),
      (
        'widget_ime_name_on_linux',
        'parent',
        payload.processes.parent.keyed_scalars.widget_ime_name_on_linux
      ),
      (
        'widget_ime_name_on_mac',
        'parent',
        payload.processes.parent.keyed_scalars.widget_ime_name_on_mac
      ),
      (
        'widget_ime_name_on_windows',
        'parent',
        payload.processes.parent.keyed_scalars.widget_ime_name_on_windows
      )
    ] AS metrics
  FROM
    filtered
),
flattened_metrics AS (
  SELECT
    sample_id,
    client_id,
    submission_date,
    os,
    app_version,
    app_build_id,
    channel,
    metrics.name AS metric,
    metrics.process AS process,
    value.key AS key,
    value.value AS value
  FROM
    grouped_metrics
  CROSS JOIN
    UNNEST(metrics) AS metrics,
    UNNEST(metrics.value) AS value
),
sampled_data AS (
  SELECT
    *
  FROM
    flattened_metrics
  WHERE
    channel IN ("nightly", "beta")
    OR (channel = "release" AND os != "Windows")
  UNION ALL
  SELECT
    *
  FROM
    flattened_metrics
  WHERE
    channel = 'release'
    AND os = 'Windows'
    AND sample_id >= @min_sample_id
    AND sample_id <= @max_sample_id
),
-- Using `min` for when `agg_type` is `count` returns null when all rows are null
aggregated AS (
  SELECT
    submission_date,
    sample_id,
    client_id,
    os,
    app_version,
    app_build_id,
    channel,
    metric,
    key,
    process,
    SUM(CASE WHEN value = TRUE THEN 1 ELSE 0 END) AS true_col,
    SUM(CASE WHEN value = FALSE THEN 1 ELSE 0 END) AS false_col
  FROM
    sampled_data
  GROUP BY
    submission_date,
    sample_id,
    client_id,
    os,
    app_version,
    app_build_id,
    channel,
    metric,
    process,
    key
)
SELECT
  sample_id,
  client_id,
  submission_date,
  os,
  app_version,
  app_build_id,
  channel,
  ARRAY_CONCAT_AGG(
    ARRAY<
      STRUCT<
        metric STRING,
        metric_type STRING,
        key STRING,
        process STRING,
        agg_type STRING,
        value FLOAT64
      >
    >[
      (metric, 'keyed-scalar-boolean', key, process, 'true', true_col),
      (metric, 'keyed-scalar-boolean', key, process, 'false', false_col)
    ]
  ) AS scalar_aggregates
FROM
  aggregated
GROUP BY
  sample_id,
  client_id,
  submission_date,
  os,
  app_version,
  app_build_id,
  channel
