# Operação do ATLAS

## Acessos

O master gerencia empresas globalmente. Use o seletor de empresa no menu lateral para entrar em uma empresa à qual sua conta está vinculada; “Administração” passa a mostrar a equipe e configurações dessa empresa. O seletor oferece retorno à administração global para contas master.

Funcionários têm permissões explícitas. Para operar empréstimos, conceda leitura de clientes, leitura/criação de contratos e as permissões de pagamentos pertinentes. Exportar relatórios não concede automaticamente leitura de todos os módulos. Documentos têm permissões próprias. Cobradores não recebem funções financeiras administrativas.

A tabela de auditoria registra decisões administrativas e eventos financeiros. O último administrador ativo da empresa não pode ser removido ou desativado.

## Contratos, multa e recebimento

Os juros são simples e fixados no cadastro. As parcelas distribuem todo o total a centavos. A prévia é calculada no servidor; o banco revalida valores e datas para impedir alteração maliciosa do calendário. Termos financeiros não são editáveis após criação.

Mensal: uma cobrança em mês real, com ajuste de fim de mês. Diário: primeira parcela no dia seguinte, incluindo ou excluindo domingos; multa única por bloco completo de dias consecutivos em atraso. Semanal: primeira cobrança após sete dias e multa por dia de cada parcela vencida. Parcela parcialmente paga continua sujeita à multa fixa. Multas consolidadas permanecem devidas até pagamento ou concessão registrada.

Recebimentos alocam primeiro às parcelas mais antigas e depois às multas. A quitação negociada registra o desconto explicitamente. Renovação mensal exige juros mais multas e não capitaliza juros; não é permitida após amortização do principal no ciclo. Regularização diária/semanal paga vencidas e multas e segue o calendário remanescente; se não restar saldo, encerra o contrato. Para novo crédito, crie outro contrato.

O registro é feito na data atual de São Paulo. Não há alteração retroativa da data de recebimento. Uma renovação com eventos posteriores não pode ser estornada isoladamente, pois isso invalidaria esses eventos; reverta primeiro os eventos dependentes.

Pagamentos, despesas e ajustes têm estorno auditado. Liberações de crédito não são apagadas pela tela de caixa. Confira contrato e beneficiário antes de liberar principal.

## Fechamento e relatórios

Selecione a data no caixa e confirme o fechamento. É possível recalcular o fechamento da mesma data. Após novos lançamentos com data anterior, refaça os fechamentos afetados: o fechamento é um registro da conciliação no momento em que foi confirmado.

CSV e XLSX limitam exportação a 10.000 registros; PDF a 1.000. A mensagem de limite pede um período menor. CSV neutraliza células que poderiam virar fórmulas; XLSX grava valores de texto sem fórmulas. PDF oferece uma relação textual paginada; impressão de fechamento tem layout próprio.

Os documentos são privados e só geram links temporários após autorização. Use arquivos JPG/PNG/PDF de até 4 MiB. Para substituir, envie a versão nova e remova a anterior. WhatsApp apenas abre uma conversa com o texto escolhido: não envia mensagens automaticamente.

## Privacidade e retenção

O operador define seus textos de privacidade e termos nas configurações, base de tratamento, retenção, atendimento a titulares e processo de exclusão. Não existe índice de CPF compartilhado entre empresas. Não exporte dados para repositórios públicos. A existência de controles técnicos não representa certificação jurídica.

## Homologação externa

Antes de usar com clientes reais, valide convites/recuperação recebidos no e-mail, redirecionamentos de produção, telas em celular/desktop, impressão e permissões com usuários reais de homologação. O navegador remoto não estava disponível na sessão de implementação; testes HTTP não comprovam aparência ou usabilidade visual. SMTP e Auth URL Configuration precisam ser conferidos no painel do Supabase.
