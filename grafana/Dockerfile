FROM grafana/grafana:11.4.0
RUN grafana-cli plugins install grafana-azure-data-explorer-datasource && \
    grafana-cli plugins install pixie-pixie-datasource

COPY --chown=grafana:root provisioning /etc/grafana/provisioning