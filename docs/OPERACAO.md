# Operação do ATLAS

## Acessos

O master administra solicitações, empresas e usuários pela área Administração global. O acesso operacional a uma empresa exige vínculo ativo próprio; contas sem esse vínculo não entram nos módulos da empresa. O administrador do tenant gerencia sua equipe e operação apenas dentro do próprio tenant.

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

Antes de usar com clientes reais, valide telas em celular/desktop, impressão e permissões com usuários de homologação. O acesso é configurado manualmente, sem confirmação ou recuperação por e-mail. O navegador remoto pode não estar disponível em toda sessão; compilação e testes HTTP não comprovam aparência visual em todos os dispositivos.

## Cadastro completo do cliente

O cadastro e a ficha usam os grupos Dados do cliente, Contato familiar, Informações auxiliares e Documentos e anexos. CPF, CEPs e WhatsApps têm máscaras; o servidor normaliza os números e valida CPF, e-mail e comprimento de CEP/telefone. E-mails são salvos sem espaços nas pontas e em minúsculas.

Ao completar os oito dígitos de qualquer um dos CEPs, o sistema consulta o [ViaCEP](https://viacep.com.br/) e preenche o endereço correspondente. Complete número e complemento. CEP não encontrado ou indisponibilidade do serviço exibem mensagem e permitem preenchimento manual. Só o CEP é enviado ao serviço externo.

Os documentos são Foto do RG, Selfie com documento, Comprovante de residência, Comprovante do comércio, Foto da frente da casa (opcional), Foto da frente do comércio (opcional) e Comprovante PIX enviado ao cliente. Documentos antigos continuam acessíveis. No cadastro, selecione os arquivos antes de salvar; se algum envio falhar, os dados ficam salvos e os anexos pendentes podem ser reenviados sem criar outro cliente. Na ficha, cada anexo pode ser visualizado dentro do sistema, aberto em outra aba ou removido com confirmação.

## Contas e senhas sem e-mail

O administrador cria as contas pelo menu Administração, informa o e-mail de login e define a senha temporária. A conta Auth é marcada como confirmada pelo servidor; não há envio de convite. No primeiro acesso, o sistema exige a troca da senha antes de liberar qualquer outro módulo. Na fila global, o master define a senha temporária ao aprovar a empresa. Redefinições pelo master também exigem troca no próximo acesso. A recuperação por e-mail está desativada. Entregue senhas temporárias por canal privado. A opção de cadastros públicos permanece desativada; o e-mail continua sendo somente identificador de login.

Solicitações de empresa recebem um código de acompanhamento mostrado uma única vez na tela; o solicitante deve copiá-lo. A consulta manual informa se o pedido está pendente, aprovado ou rejeitado. Nenhuma atualização é enviada por e-mail. Formulário público, consulta de status e login têm limites de tentativas por endereço IP.
