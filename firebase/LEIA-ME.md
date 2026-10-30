# Nuvem (Firebase) — guia rápido da versão 1.0

O projeto Firebase `ibmmkardatabank` e o espaço da igreja já vêm configurados dentro do app.
O que falta fazer é só isto:

## 1. Publicar as novas regras (obrigatório)
1. Console do Firebase ▸ **Firestore Database ▸ Regras**.
2. Apague tudo, cole o conteúdo de `firebase/firestore.rules` e clique em **Publicar**.

> Sem isso, as contas de membro e inspetor não ficam restritas no servidor.

## 2. Login por e-mail e senha
Console ▸ **Authentication ▸ Método de login ▸ E-mail/senha** precisa estar **ativado**
(o login com Google não é mais usado).

## 3. Conta principal (dona do espaço)
A conta `ibmmkarsecretaria@gmail.com` é a dona. Se ela foi criada antes pelo Google e
ainda não tem senha: na tela de entrada do app, digite o e-mail e toque em
**Esqueci a senha**; defina uma senha pelo link recebido e entre normalmente.

## 4. Como funcionam as contas
| Papel | O que pode |
|---|---|
| **Dono** | Tudo, e define o papel das outras contas (Minha conta ▸ Contas e permissões) |
| **Secretaria** | Ver e editar tudo |
| **Inspetor** | Ver tudo, sem alterar nada |
| **Membro** | Só o Mural e a Agenda (avisos, cultos, eventos, publicações) |

- Quem cria conta entra como **Membro**.
- Quem escolhe **Secretaria** ao criar a conta fica como Membro até a conta dona **aprovar**
  (os pedidos aparecem no topo de *Contas e permissões*).
- Qualquer conta pode ser **bloqueada** pela dona.

## 5. Mural, cultos e publicações
- **Cultos da semana** (Mural ▸ "Cultos da semana"): repetem toda semana, com título e cronograma editáveis.
- **Versículo do dia**: crie um *evento* do tipo "Versículo do dia" (título = referência, detalhes = texto).
- **Publicar no Mural**: nas Listas e nas Atas, menu da lista/ata ▸ *Publicar no Mural* (7, 15 ou 30 dias).
  A publicação some sozinha no prazo; é uma cópia do conteúdo do momento.

## 6. Fale conosco
No fim do Mural, só a **conta dona** vê o botão *Editar* para definir telefone, e-mail e endereço
da igreja. Todos os papéis veem. (As regras do passo 1 também impedem a edição por outras contas.)

## 7. Dicas
- Ao **sair da conta**, os dados salvos no aparelho são apagados (continuam na nuvem).
- Fotos muito grandes (> ~900 KB) ficam só no aparelho; as feitas pelo app já são reduzidas.
- Os eventos da agenda passam a ficar numa coleção própria; a migração é automática no
  primeiro sincronismo da conta dona.
