# ATLAS — gestão de empréstimos

Acesso publicado: https://atlas-gestao-xi.vercel.app · Código: https://github.com/atlascred/atlas-gestao

Aplicação em português do Brasil com Next.js, TypeScript, Supabase Auth/PostgreSQL/Storage. Identidade visual baseada no logotipo ATLAS. Não há assinatura, trial ou cobrança SaaS.

## Funcionalidades

- Aprovação de empresas pelo administrador global; suspensão e reativação auditadas. O acesso operacional depende de empresa aprovada e vínculo ativo.
- Login, convite, recuperação e troca de senha, perfil, seleção de empresa, equipe e permissões por funcionário. Cobradores consultam somente clientes atribuídos.
- Clientes com CPF validado, ficha completa, histórico financeiro, contato pelo WhatsApp e documentos privados JPG/PNG/PDF de até 4 MiB.
- Empréstimos diários, semanais e mensais; juros simples; HALF_UP; divisão exata dos centavos; calendário com opção de excluir domingos; prévia calculada no servidor. Termos financeiros imutáveis.
- Recebimentos parciais, renovação mensal, regularização de vencidas, quitação negociada, multas e estornos. Operações financeiras usam transações, idempotência, trilha de auditoria e movimentos de caixa.
- Despesas, ajustes de caixa, estornos de despesas/ajustes e fechamento por data. Dashboard com dados persistentes e sem números fictícios.
- Relatórios de clientes, contratos, parcelas, atrasos, recebimentos, despesas, caixa e fechamentos em CSV, XLSX e PDF. Até 10.000 registros por planilha e 1.000 por PDF; reduza o período para volumes maiores.
- Administração global pesquisável/paginada, recuperação de senha por e-mail, alteração de acesso e auditoria. Configurações de nome, logotipo, favicon, mensagem de cobrança e textos de privacidade/termos por empresa.

## Executar localmente

Node.js 22 e npm:

```sh
cp .env.example .env.local
npm ci
npm run dev -- --hostname 127.0.0.1
```

Abra http://127.0.0.1:3000/login. Configure as variáveis antes de usar os módulos:

| Variável | Uso |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | URL pública do projeto Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Chave publicável ou anon; RLS continua obrigatório |
| `SUPABASE_SERVICE_ROLE_KEY` | Chave secret/service role, somente no servidor |
| `NEXT_PUBLIC_SITE_URL` | URL canônica da aplicação, sem barra final |
| `MASTER_BOOTSTRAP_SECRET` | Segredo temporário para criar o primeiro master |
| `ATLAS_LOGIN_ALIAS`, `ATLAS_LOGIN_EMAIL` | Alias opcional de login associado a um e-mail real |

As chaves modernas `sb_publishable_…` e `sb_secret_…` são aceitas. Nunca prefixe o segredo administrativo com `NEXT_PUBLIC_`. A senha PostgreSQL não é uma chave API e não é necessária no runtime da aplicação. `.env.local` não deve ser versionado.

## Banco e autenticação

As migrations em `supabase/migrations` devem ser aplicadas na ordem, uma vez por versão. Há isolamento RLS nas tabelas e nos buckets privados `client-documents` e `tenant-branding`.

```sh
npx supabase login
npx supabase link --project-ref SEU_PROJECT_REF
npx supabase db push
```

Em um projeto já existente, confira primeiro o histórico remoto. Não aplique novamente uma migration já registrada. Faça backup antes de migrar uma base com dados reais.

No painel Supabase:

1. **Authentication → URL Configuration**: configure Site URL e permita as URLs da aplicação para `/login`, `/auth/callback` e `/auth/callback?next=%2Ftrocar-senha`. Inclua também localhost se usar desenvolvimento.
2. **Authentication**: desative a opção de permitir novos cadastros públicos, mantendo o provedor Email habilitado para login e convites. Na CLI, use `auth.enable_signup = false` e `auth.email.enable_signup = true`. O cadastro público do ATLAS registra uma solicitação, sem conceder acesso operacional.
3. Configure SMTP para entrega real de convites e recuperação. O serviço de e-mail padrão do provedor tem restrições e cotas; um retorno de API não comprova recebimento na caixa de entrada.
4. Crie e confirme a primeira conta administrativa usando procedimento seguro no Supabase. Configure `MASTER_BOOTSTRAP_SECRET`, faça login e abra `/iniciar-master`. O bootstrap transacional só permite o primeiro master. Remova esse segredo depois.
5. O master aprova solicitações; o administrador convidado define a própria senha e acessa sua empresa. Ser master não cria automaticamente vínculo operacional com todas as empresas.

## Regras financeiras e operação

Veja [operação e limites](docs/OPERACAO.md). Recebimentos são lançados na data de registro; não há lançamento retroativo que reescreva multas e pagamentos posteriores. Corrija com estorno auditado e novo lançamento. A renovação mensal preserva o dia-base; regularização diária/semanal recebe vencidas e multas e mantém o calendário futuro existente. Quando não há saldo remanescente, o contrato é quitado, sem criar dívida nova automaticamente.

Os relatórios financeiros não substituem conciliação com contas bancárias. Revise a data e os valores antes de confirmar qualquer recebimento real.

## Verificações

```sh
npm run lint
npx tsc --noEmit
npm test
npm run build
npm audit --omit=dev
```

Testes SQL transacionais usam fixtures sintéticas e terminam em `ROLLBACK`. Execute preferencialmente em homologação com conexão administrativa, fornecida pelo ambiente, sem colocar a URL em arquivos versionados:

```sh
psql "$DIRECT_URL" -X -v ON_ERROR_STOP=1 -f supabase/tests/financial_rpc_smoke.sql
psql "$DIRECT_URL" -X -v ON_ERROR_STOP=1 -f supabase/tests/lifecycle.sql
psql "$DIRECT_URL" -X -v ON_ERROR_STOP=1 -f supabase/tests/access_and_reversal.sql
```

Cobrem isolamento de tenant, restrição do cobrador, autorização master, último administrador, caixa, idempotência, parcelas, multas, quitação, renovação e estorno. A CI executa lint, testes e build sem segredos reais. Uma compilação bem-sucedida não substitui teste visual e entrega de e-mails no ambiente publicado.

## GitHub e Vercel

O repositório contém apenas código, migrations, testes sintéticos e recursos de marca. `.env*`, credenciais, uploads, dumps e artefatos locais não devem ser publicados. Confira `git diff --cached` antes de cada envio.

Importe o repositório na Vercel como Next.js, Node 22. Configure as variáveis públicas e o segredo de servidor em Production (e Preview somente quando houver banco de homologação). Configure `NEXT_PUBLIC_SITE_URL` para o domínio publicado. Não publique o segredo de bootstrap depois de concluído. Cada alteração de variável pública exige novo build.

```sh
npx vercel link
npx vercel --prod
```

A aplicação usa o SDK HTTPS do Supabase no runtime, sem pools PostgreSQL locais e sem persistência em disco. Uploads têm limite abaixo do payload das funções; quotas e limites dos provedores devem ser conferidos no painel do plano utilizado. O domínio padrão Vercel já atende o HTTPS; domínio próprio é opcional.

## Segurança, backup e problemas comuns

Veja [operação e limites](docs/OPERACAO.md) e [backup/restore](docs/BACKUP.md).

- **Sessão inválida**: entre novamente; confira URL/chave pública e os cookies. Reinicie o servidor após modificar `.env.local`.
- **Acesso negado**: confira empresa selecionada, aprovação, vínculo ativo e permissões. Não desative RLS para contornar erros.
- **Convite/recuperação não chega**: revise SMTP, redirecionamentos, spam e limites de e-mail do Supabase.
- **Arquivo indisponível**: links expiram; use “Atualizar links de acesso” na ficha do cliente.
- **Falha ao gerar relatório**: reduza o período e confira permissões de leitura dos módulos e exportação.
- **Correção financeira**: use estorno; não edite ou apague lançamentos diretamente no banco.
