/// Endereço da API. Em produção é o domínio da oficina; para outro servidor,
/// use: flutter run --dart-define=API_URL=https://meu-servidor
const String kApiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://telemetria-tcc.duckdns.org',
);

const String kAppVersion = '2.0.0';
