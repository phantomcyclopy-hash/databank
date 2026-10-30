/// Dados fixos do Firebase deste app. A chave de API da Web não é segredo
/// (quem protege os dados são as regras do Firestore).
const String kFirebaseApiKey = 'AIzaSyBGNsOH-2Kc67ZGeWRkl8wiiPAp8LGBGyI';
const String kFirebaseProjeto = 'ibmmkardatabank';

/// Espaço único da igreja (igrejas/{kEspacoId} no Firestore).
const String kEspacoId = 'sep67ywshq';

/// Conta principal: dona do espaço, concede e retira permissões.
const String kDonoEmail = 'ibmmkarsecretaria@gmail.com';

/// Papéis: dono, secretaria (edita tudo), inspetor (vê tudo, não edita),
/// membro (só Mural e Agenda) e bloqueado (sem acesso).
const Map<String, String> kPapeis = {
  'dono': 'Dono',
  'secretaria': 'Secretaria',
  'inspetor': 'Inspetor',
  'membro': 'Membro',
  'bloqueado': 'Bloqueado',
};
