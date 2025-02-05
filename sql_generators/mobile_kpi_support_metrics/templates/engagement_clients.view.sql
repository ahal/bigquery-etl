{{ header }}
CREATE OR REPLACE VIEW
  `{{ project_id }}.{{ dataset }}.{{ name }}`
AS
WITH active_users AS (
  SELECT
    submission_date,
    client_id,
    sample_id,
    first_seen_date,
    app_name,
    normalized_channel,
    locale,
    country,
    isp,
    app_display_version,
    is_dau,
    is_wau,
    is_mau,
    is_mobile,
  FROM
    `{{ project_id }}.{{ dataset }}.active_users`
),
attribution AS (
  SELECT
    client_id,
    sample_id,
    channel AS normalized_channel,
    NULLIF(adjust_ad_group, "") AS adjust_ad_group,
    NULLIF(adjust_creative, "") AS adjust_creative,
    NULLIF(adjust_network, "") AS adjust_network,
    {% if app_name == "fenix" %}
      CASE
        WHEN adjust_network IN ('Google Organic Search', 'Organic')
          THEN 'Organic'
        ELSE NULLIF(adjust_campaign, "")
      END
    {% else %}
      NULLIF(adjust_campaign, "")
    {% endif %} AS adjust_campaign,
    {% for field in product_specific_attribution_fields %}
      {% if field.type == "STRING" %}
        NULLIF({{ field.name }}, "") AS {{ field.name }},
      {% else %}
        {{ field.name }}
      {% endif %}
    {% endfor %}
  FROM
    {% if app_name == "fenix" %}
      `{{ project_id }}.{{ dataset }}_derived.firefox_android_clients_v1`
    {% elif app_name == "firefox_ios" %}
      `{{ project_id }}.{{ dataset }}_derived.firefox_ios_clients_v1`
    {% endif %}
)
SELECT
  submission_date,
  client_id,
  sample_id,
  first_seen_date,
  app_name,
  normalized_channel,
  app_display_version AS app_version,
  locale,
  country,
  isp,
  is_dau,
  is_wau,
  is_mau,
  is_mobile,
  attribution.adjust_ad_group,
  attribution.adjust_campaign,
  attribution.adjust_creative,
  attribution.adjust_network,
  {% for field in product_specific_attribution_fields %}
    attribution.{{ field.name }},
  {% endfor %}
  CASE
    WHEN active_users.submission_date = first_seen_date
      THEN 'new_profile'
    WHEN DATE_DIFF(active_users.submission_date, first_seen_date, DAY)
      BETWEEN 1
      AND 27
      THEN 'repeat_user'
    WHEN DATE_DIFF(active_users.submission_date, first_seen_date, DAY) >= 28
      THEN 'existing_user'
    ELSE 'Unknown'
  END AS lifecycle_stage,
FROM
  active_users
LEFT JOIN
  attribution
  USING (client_id, sample_id, normalized_channel)
