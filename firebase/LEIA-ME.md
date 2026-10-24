# Configurar a nuvem (Firebase) — passo a passo

O app guarda tudo no aparelho e, se você ligar a nuvem, sincroniza entre os celulares.
Você só precisa fazer isto **uma vez**. O plano gratuito (Spark) do Firebase é suficiente.

## 1. Criar o projeto
1. Abra https://console.firebase.google.com e entre com sua conta Google.
2. **Adicionar projeto** → dê um nome (ex.: `ibmmkar`) → pode desativar o Google Analytics → **Criar**.

## 2. Ativar o login
1. Menu **Build ▸ Authentication ▸ Vamos começar**.
2. Aba **Método de login**:
   - **E-mail/senha** → ativar → Salvar.
   - **Google** → ativar → escolha um e-mail de suporte → Salvar.
3. Ainda em **Google**, abra **Configuração do SDK da Web** e copie o **ID do cliente da Web** (termina com `.apps.googleusercontent.com`). Você vai colar no app.

## 3. Criar o banco (Firestore)
1. Menu **Build ▸ Firestore Database ▸ Criar banco de dados**.
2. Modo **produção**; local sugerido: `southamerica-east1` (São Paulo) → **Ativar**.
3. Aba **Regras**: apague tudo, cole o conteúdo do arquivo `firebase/firestore.rules` deste projeto e clique em **Publicar**.

## 4. Pegar os dados do projeto
**Engrenagem ▸ Configurações do projeto ▸ Geral**:
- **ID do projeto** (Project ID);
- **Chave de API da Web** (Web API Key).

## 5. Só para "Entrar com Google" no Android
Em **Configurações do projeto ▸ Seus apps ▸ Adicionar app ▸ Android**:
- **Nome do pacote:** `com.example.databank_app`
- **Certificado SHA-1:** `3D:CE:7E:A6:7E:4B:14:F8:5C:05:DF:63:47:04:78:1A:D3:C4:32:0A`
- Pode clicar em Registrar e **pular** o download do `google-services.json` (o app não usa).

> O SHA-1 acima é o da chave fixa do projeto (`tool/debug.keystore`). Se você trocar essa chave, registre o novo SHA-1.

## 6. No app
1. **Mural ▸ ícone de nuvem** (canto superior).
2. Cole **Chave de API**, **ID do projeto** e (se for usar Google) o **ID do cliente web** → *Salvar dados do projeto*.
3. **Entrar** / **Criar conta** (e-mail e senha) ou **Entrar com Google**.
4. No **primeiro aparelho**: *Criar espaço da igreja*. Anote o **ID** e o **código**.
5. Nos **outros aparelhos**: configure o projeto, entre com uma conta e use *Já existe um espaço?* com o ID e o código.
6. Pronto: *Sincronizar agora* ou deixe no automático.

## Dicas
- **Antes de ligar a nuvem pela primeira vez**, use *Membros ▸ ⋮ ▸ Backup completo* para ter uma cópia.
- No Windows o login com Google não está disponível; use e-mail e senha.
- Quem tem o ID e o código entra no espaço. Guarde-os como uma senha.
- Fotos muito grandes (> ~900 KB) ficam só no aparelho; fotos tiradas pelo app já são reduzidas.
