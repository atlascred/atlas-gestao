# Backup e recuperação

O ATLAS não mantém backups automáticos próprios e não usa arquivos locais como banco. Confira no painel Supabase as opções e retenção disponíveis no seu plano; não presuma que há recuperação pontual configurada.

## Procedimento testável

1. Use uma máquina administrativa e um diretório criptografado fora do repositório. Obtenha a conexão de sessão (porta 5432) no painel. Forneça credenciais pelo ambiente/gerenciador de segredos, não em comandos salvos no histórico.
2. Exporte schema e dados com os comandos oficiais da CLI Supabase (`supabase db dump`), separando schema, roles e dados conforme a documentação da versão instalada. Preserve o histórico de migrations. CSVs da interface são relatórios e não substituem um dump relacional.
3. Exporte separadamente os objetos dos buckets privados via Storage API/CLI autorizada. Um dump de metadados do Storage não contém o conteúdo binário dos documentos. Registre checksums e caminhos relativos; mantenha o material criptografado e com acesso restrito.
4. Preserve a estratégia de migração/restauração de usuários Auth: os vínculos usam UUIDs de usuários. Nunca recrie usuários com novos IDs sem migrar os vínculos de forma planejada.
5. Restaure primeiro em um projeto de homologação vazio, usando o procedimento de restauração suportado pela CLI/Supabase, incluindo Auth, schema, dados e objetos. Não teste restauração por cima da base de produção.
6. Compare contagens por empresa, somas do ledger, parcelas e alocações; rode os testes SQL transacionais deste repositório. Verifique login, isolamento entre empresas e download de um documento privado com checksum correspondente.
7. Registre data, versão da CLI, checksums, duração e resultado. Só depois aprove um procedimento de recuperação de produção. Faça ensaios periódicos e mantenha mais de uma cópia protegida.

Nenhum ensaio completo de recuperação de produção ou agendamento automático é declarado por este projeto. A execução depende de um projeto de homologação e das credenciais administrativas do operador.
