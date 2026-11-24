---
title: Gerenciar dados no painel — busca, filtros, relacionamentos, campos travados e criar/editar/excluir declarados
status: proposed
created: 2026-11-24
updated: 2026-11-24
owner: "@oporpino"
certainty: high
---

# Gerenciar dados no painel — busca, filtros, relacionamentos, campos travados e criar/editar/excluir declarados

> **TLDR**: o operador passa a buscar, filtrar e ordenar pelas **colunas visíveis**: públicas sempre, mascaradas só com revelação ativa e com o critério guardado no servidor (ADR 0001). Também navega por chaves estrangeiras e por "Relacionados", e cria, edita ou exclui registros nas tabelas que o app declarar (`creatable`, `editable`, `destroyable`), sempre como Ação: motivo, prévia, permissão e evento. Campos de colunas mascaradas aparecem travados com bolinhas até a revelação, o que fecha o vazamento atual do `initial_values`. Ações ganham **opções de envio** (vários botões de execução, cada um podendo sumir), **segredo de exibição única** (um valor mostrado uma vez para copiar) e **e-mail disponível** (`email_available?`, sem conhecer provedor). Entrega a gem 0.4.0 e exemplos no luneta: "Novo usuário" com "Criar e enviar por e-mail" ou "Criar e copiar link", "Gerar link de definição de senha" e `classrooms`.

Spec 2 de 2. Depende de `20261124100000_panel_layout_and_reveal_eye.md` (sidebar, cabeçalho de página, Ações no cabeçalho, olho). Decisões: `docs/adr/0001-search-revealed-columns-server-side.md` (gem) e ADR 0004 do luneta (`~/workspace/brazza.tech/lunetamagica/docs/adr/0004-own-sysadmin-panel-masked-by-default.md`), que segue valendo para escrita: só Ações curadas, agora também derivadas de declaração. Glossário: `docs/CONTEXT.md`.

# what

Como operador do painel, quero achar registros por busca e filtros, navegar entre registros relacionados e criar, editar ou excluir registros nas tabelas que o app liberou, sempre com motivo e rastro, para operar o dia a dia sem pedir mudança no banco a um dev.

## out of scope

- CRUD genérico em tabela não declarada: tabela sem `creatable`, `editable` ou `destroyable` continua só leitura (ADR 0004).
- Ações em lote (bulk) e importação/exportação CSV.
- Busca em coluna mascarada sem revelação ativa, e qualquer critério em coluna oculta (`secret` ou `hide`).
- Associações polimórficas (`*_type` + `*_id`) como link: aparecem como valor simples.
- Menus de plugin por contexto de tenant (issue separada, aberta na Spec A).
- A gem enviar e-mail ou conhecer provedor (Resend, Postmark...): ela só pergunta ao app se há e-mail (`email_available`), e quem envia é a Ação do app.
- Luneta: o admin da escola criando usuários (já existe em `Settings::UsersController`), troca de senha obrigatória no primeiro acesso, senha temporária exibida em claro e Ações de criação para outras tabelas além de `users` e `classrooms`.
- Feature flag: não há (ver `# how`).

## acceptance criteria

    Cenário: buscar por coluna pública
      Dado a tabela "users" com a coluna pública "role"
      Quando o operador filtra "role = teacher"
      Então a lista mostra só usuários com role "teacher"
      E a URL contém "filter[role]=teacher"

    Cenário: coluna mascarada não é filtrável sem revelação
      Dado a coluna "email" de categoria "contact" e nenhuma revelação ativa
      Quando o operador abre "+ Filtro"
      Então "email" não aparece entre as colunas filtráveis
      E "GET ...?filter[email]=x" ignora o critério e mostra o aviso de filtro ignorado

    Cenário: coluna revelada fica pesquisável, com o critério no servidor
      Dado o operador com revelação ativa no contexto
      Quando ele busca "maria" em "users"
      Então a lista mostra os usuários cujo name ou email contém "maria" (sem diferenciar maiúsculas)
      E a URL contém só "q=<token>" e nenhum trecho de "maria"
      E o evento "backoffice.browse" registra as colunas usadas e não o texto buscado

    Cenário alternativo: revelação acaba com o filtro aplicado
      Dado uma lista aberta com "?q=<token>" que filtra por "email"
      Quando a revelação expira ou é encerrada
      E o operador recarrega a página
      Então o critério de "email" é ignorado e a página avisa "Filtro em coluna mascarada ignorado: email"

    Cenário alternativo: coluna oculta nunca é critério
      Dado a coluna "encrypted_password" em hide e a coluna "api_token" de categoria "secret"
      Quando o operador envia um critério por qualquer uma delas, com ou sem revelação
      Então o critério é ignorado e nenhum SQL com essas colunas no WHERE ou no ORDER BY é executado

    Cenário: ordenar por coluna visível
      Quando o operador clica no cabeçalho "created_at"
      Então a lista é ordenada por created_at crescente, e um segundo clique inverte
      E colunas mascaradas não reveladas não têm link de ordenação

    Cenário: link de chave estrangeira
      Dado "classrooms.grade_id" com foreign key para "grades"
      Quando o operador abre a lista de "classrooms"
      Então o valor de grade_id é um link para o registro de "grades" no mesmo contexto

    Cenário: Relacionados
      Dado o usuário 42 referenciado por 3 linhas de "enrollments.user_id"
      Quando o operador abre o registro 42 de "users"
      Então o card "Relacionados" mostra "enrollments 3" com link para a lista de enrollments filtrada por user_id = 42

    Cenário: criar um registro declarado
      Dado um Resource com "creatable :name, :email, :role" e o operador com a permissão create_record
      Quando o operador clica em "Novo registro" na lista de "users", preenche os campos, a prévia e o motivo
      Então o registro é criado pelo model (ou pelo Command de with:)
      E um evento "backoffice.action.create_users" é gravado com o motivo
      E o operador vai para a página do registro criado

    Cenário alternativo: criar falha por validação
      Quando o model ou o Command recusa os dados
      Então nada é gravado, o formulário volta com a mensagem de erro e os campos preenchidos

    Cenário alternativo: tabela não declarada
      Dado a tabela "messages" sem Resource com creatable
      Quando o operador abre a lista
      Então não há "Novo registro"
      E "GET /backoffice/actions/create_messages/new" responde 404

    Cenário alternativo: sem permissão
      Dado um operador sem create_record
      Quando ele abre a lista de "users"
      Então "Novo registro" não aparece e o POST da ação responde 403

    Cenário: campo travado na edição
      Dado "editable :name, :email" em "users", "email" de categoria "contact" e nenhuma revelação ativa
      Quando o operador abre "Editar" no usuário 42
      Então "name" é um input com o valor atual
      E "email" é um campo desabilitado com "•••••" e o aviso "Revele os dados para editar"
      E o HTML da página não contém o e-mail do usuário

    Cenário: campo destrava com a revelação
      Dado o operador com revelação ativa no contexto
      Quando ele abre "Editar" no usuário 42
      Então "email" é um input com o e-mail atual

    Cenário alternativo: campo travado enviado à força
      Dado "email" travado
      Quando um POST da ação envia fields[email]=outro@x.com
      Então o valor enviado é descartado e o email do registro não muda

    Cenário alternativo: Command recebe o valor atual do campo travado
      Dado "editable ..., with: Organization::Update" com "cnpj" travado
      Quando o operador salva a edição de outros campos
      Então o Command recebe cnpj com o valor atual do registro (lido no servidor), e o cnpj não vira nil

    Cenário: excluir um registro declarado
      Dado "destroyable" em "classrooms" e o operador com destroy_record
      Quando ele escolhe "Excluir registro" no menu de Ações, digita o id para confirmar e informa o motivo
      Então o registro é excluído, um evento "backoffice.action.destroy_classrooms" é gravado e o operador volta à lista

    Cenário alternativo: exclusão recusada pelo model
      Dado uma classroom com enrollments (dependent: :restrict_with_error)
      Quando o operador tenta excluí-la
      Então nada é excluído e a mensagem de erro do model aparece

    Cenário: opções de envio viram botões
      Dado uma Ação com "submit :email, label: 'Enviar por e-mail', if: -> { email_available? }" e "submit :link, label: 'Copiar link'"
      E o app com e-mail disponível
      Quando o operador chega à etapa final (prévia e motivo)
      Então há dois botões, "Enviar por e-mail" e "Copiar link", no lugar de "Executar"
      E o botão clicado chega à Ação como submitted (e ao Command de with: como o atributo submit, se ele o declarar)

    Cenário alternativo: opção indisponível some
      Dado a mesma Ação e o app sem e-mail disponível
      Quando o operador chega à etapa final
      Então só o botão "Copiar link" aparece
      E um POST com submit=email responde com falha "invalid" e nada é executado

    Cenário alternativo: Ação sem submit declarado
      Dado uma Ação sem nenhum submit
      Então a etapa final mostra o único botão "Executar", como hoje

    Cenário: e-mail disponível lido do Rails
      Dado o ActionMailer com delivery_method :smtp e smtp_settings[:address] "smtp.provedor.com"
      Então email_available? é verdadeiro
      E com address ausente ou "localhost" (o default do Rails) é falso
      E com perform_deliveries false é falso
      E com qualquer outro delivery_method registrado (:test, :file, :sendmail, de gem de provedor) é verdadeiro
      E config.email_available = -> { false } no app sobrescreve tudo

    Cenário: segredo de exibição única
      Dado uma Ação com "secret { |value| value[:link] }" que devolve um link
      Quando o operador executa com sucesso
      Então a resposta é 200 sem redirect, com Cache-Control "no-store"
      E o link aparece num campo somente leitura com o botão "Copiar" e o aviso "Copie e envie para a pessoa; não será exibido novamente"
      E o HTML não tem nenhum <a> cujo href seja o link
      E o link não está no flash, na session, no Evento de atividade nem no log da requisição
      E recarregar ou voltar não mostra o link de novo

    Cenário alternativo: segredo vazio segue o fluxo normal
      Quando o bloco secret devolve nil
      Então a execução redireciona com o notice, como hoje

    Cenário: luneta, novo usuário por e-mail
      Dado o luneta com lucid-backoffice v0.4.0, e-mail configurado e um superadmin no contexto da escola "meucaminhar"
      Quando ele clica em "Novo usuário" na lista de "users", informa nome, e-mail, papel "owner" e motivo e clica em "Criar e enviar por e-mail"
      Então o usuário é criado com uma senha aleatória que ninguém vê
      E depois do commit o e-mail de definição de senha é enviado com links no host "meucaminhar.<base_domain>"
      E o operador vai para o registro criado

    Cenário: luneta, novo usuário por link
      Dado o mesmo superadmin
      Quando ele cria o usuário clicando em "Criar e copiar link"
      Então nenhum e-mail é enviado
      E a página de resultado mostra uma vez "https://meucaminhar.<base_domain>/users/password/edit?reset_password_token=<token>", válido por 6 horas

    Cenário alternativo: luneta sem e-mail configurado
      Dado production sem RESEND_API_KEY (ActionMailer em :smtp com localhost)
      Quando o superadmin abre "Novo usuário"
      Então só o botão "Criar e copiar link" aparece

    Cenário alternativo: luneta, e-mail já em uso
      Dado um usuário com e-mail "ana@escola.com" na escola
      Quando o superadmin tenta criar outro com "ana@escola.com"
      Então nada é criado, o formulário volta preenchido com a mensagem de validação do User

    Cenário alternativo: luneta, falha no envio do e-mail
      Quando o provedor de e-mail falha depois do commit
      Então o usuário continua criado, o erro vai para o log e o Sentry
      E o superadmin recupera pelo "Gerar link de definição de senha"

    Cenário: luneta, gerar link de definição de senha
      Dado um usuário existente
      Quando o superadmin executa "Gerar link de definição de senha" no registro dele, com motivo
      Então um link novo é mostrado uma vez e o link anterior deixa de valer

    Cenário: exemplos no luneta
      Dado o luneta com lucid-backoffice v0.4.0
      Quando um superadmin entra no contexto de uma escola
      Então em "users" ele pode criar ("Novo usuário") e editar (email travado até revelar)
      E em "classrooms" ele pode criar, editar o turno e excluir
      E um sysadmin "support" não vê nenhuma dessas ações, nem "Gerar link de definição de senha"

# why

O painel hoje só lê e só filtra por id na URL. Na prática:
- **Achar alguém:** o operador precisa paginar ou montar a URL na mão.
- **Navegar:** não dá para seguir `classroom_id` até a turma.
- **Criar dados:** é impossível ("não consigo adicionar um dado"), e para isso alguém abre um console Rails em produção, sem motivo nem rastro. É exatamente o risco que o ADR 0004 quis tirar.
- **DSL sem uso:** o `Resource` já declara `search`, `filter` e `association`, mas nada disso é usado em lugar nenhum.
- **Vazamento:** `Action#initial_values` põe no formulário o valor atual de colunas mascaradas, em claro (`lib/lucid/backoffice/action.rb:142`). Num `editable :cnpj` (o luneta tem `Resources::Organizations`), o operador vê o CNPJ sem ter revelado nada.

# how

Repos:
- **gem**: `~/workspace/br4zz4/lucid-backoffice`. Suíte: `bundle exec rake test`.
- **luneta**: `~/workspace/brazza.tech/lunetamagica`, app em `modules/core/code`. Suíte: `make core.test`.

Decisões de implementação:
- **Feature flag:** não há. As capacidades são aditivas e opt-in por declaração: busca e filtro só aparecem para colunas visíveis, e criar/editar/excluir só para tabelas declaradas. O campo travado é uma correção de segurança e entra sem flag.
- **Coluna utilizável** (para buscar, filtrar ou ordenar): pertence a `Records.visible` e não é oculta, e a categoria é `public` ou está em `Reveal.categories_for(operator:, tenant:)`. Uma regra só, em `Records::Query#usable?(column, revealed)`, usada pelo SQL e pela UI.
- **Critério na URL x no servidor** (ADR 0001):
  - `filter[col]=v` e `sort=col`/`dir=asc|desc` na URL só valem para colunas `public`, `id` e `*_id`.
  - Busca textual e critérios em coluna revelada vão por `POST .../data/:table/query`. O controller grava `session[:lb_queries][token] = { "table", "tenant", "filters", "search", "sort", "dir" }`, com token `SecureRandom.urlsafe_base64(12)` e no máximo 20 entradas, descartando as mais antigas. Depois redireciona para `?q=token`.
  - Token de outra tabela ou de outro contexto é ignorado.
  - O cookie de sessão do Rails é criptografado. Nenhum valor vai para a URL nem para o log; o `browse` registra só os nomes das colunas.
- **SQL:**
  - igualdade com bind para filtro;
  - `ILIKE` com `sanitize_sql_like` e bind para busca, sobre `CAST(col AS text)` nas colunas buscáveis que forem utilizáveis;
  - `ORDER BY` só por coluna utilizável e com `quote_column_name`, mais `id` como desempate.
  - Identificadores vêm só do catálogo, como hoje.
- **Colunas buscáveis:** as do `Resource.search`; sem declaração, todas as colunas de texto utilizáveis. `Resource.search` deixa de exigir `public` e passa a recusar só coluna oculta (`ConfigurationConflict`). `Resource.filter` define os filtros sugeridos no "+ Filtro"; sem declaração, todas as colunas utilizáveis aparecem.
- **Relacionamentos:** a ordem de resolução é:
  1. foreign keys do banco (`connection.foreign_keys("schema.tabela")`);
  2. `Resource.association`;
  3. convenção `x_id` → `x.pluralize`, se a tabela existir no catálogo do mesmo schema.
  "Relacionados" mostra as tabelas que apontam para a atual (foreign keys do banco mais `association` declaradas em outros Resources), no máximo 20, com `COUNT(*)` por bind.
- **Ação de registro:** `creatable`, `editable` e `destroyable` geram subclasses de `Action`, como o `editable` já faz.

  | DSL | key | alvo | permissão | label | perform padrão | depois |
  |---|---|---|---|---|---|---|
  | `creatable *cols, with:` | `create_<tabela>` | coleção da tabela | `:create_record` | "Novo registro" | `model.create!(values)` | vai para o registro criado |
  | `editable *cols, with:` | `edit_<tabela>` | registro | `:update_record` (antes `:run_action`) | "Editar" | `record.update!(values)` | volta ao registro |
  | `destroyable with:` | `destroy_<tabela>` | registro, `danger :high` | `:destroy_record` | "Excluir registro" | `record.destroy!` | vai para a lista |

  - `with: Command` passa os campos como atributos (mais `record` e `tenant`, quando declarados), como hoje.
  - **Tudo no Resource, o app só configura:** `creatable`, `editable` e `destroyable` aceitam um bloco, avaliado com `class_eval` na Action gerada **depois** dos defaults. Ali vale todo o DSL de Action: `label`, `field` (sobrescreve tipo, `choices` e `default` de um campo derivado), `submit`, `secret`, `preview`, `unavailable`, `only_if`, `redirect_to`. O app não escreve classe de Action para criar, editar ou excluir. Exemplo do luneta:

        creatable :name, :email, :role, with: User::Invite do
          label 'Novo usuário'
          field :role, :select, choices: -> { User.role.values }, default: 'owner'
          submit :email, label: 'Criar e enviar por e-mail', if: -> { email_available? }
          submit :link, label: 'Criar e copiar link'
          secret { |result| result[:set_password_url] }
        end
- **Opções de envio (`submit`):**
  - `Action.submit(key, label:, if: nil)` registra opções em ordem, e `Action.submits` as devolve. `Action#available_submits` filtra pelo `if` (avaliado na instância, com `record`, `tenant` e `email_available?`).
  - Com opções declaradas, `actions/new.html.erb` troca o "Executar" por um `submit_tag` por opção disponível, com `name: "submit"` e `value: key`, mantendo `formmethod: :post`, `disabled` até o motivo valer e o estilo `danger`.
  - O `Runner` recebe `submit:`. Com opções declaradas, um valor ausente ou fora de `available_submits` vira `failed(:invalid, ...)` antes do `perform`. Sem opções declaradas, o parâmetro é ignorado e o botão continua "Executar".
  - A instância expõe `submitted` (símbolo). O `execute` com `with:` passa `submit: submitted` quando o Command declara o atributo `submit`.
  - A prévia e o snapshot não dependem do botão.
- **E-mail disponível:**
  - `config.email_available`, uma lambda; `nil` usa o default `Lucid::Backoffice::Mail.available?`, e o app pode atribuir outra. `Action#email_available?` chama a lambda configurada.
  - Default: falso se `ActionMailer` não está carregado ou se `ActionMailer::Base.perform_deliveries` é falso. Com `delivery_method == :smtp`, verdadeiro só se `smtp_settings[:address]` estiver presente e diferente de `"localhost"`. Qualquer outro `delivery_method` conta como verdadeiro. A gem nunca cita provedor.
- **Segredo de exibição única (`secret`):**
  - `Action.secret { |value| ... }`, e `Action#secret_for(value)` devolve a string ou `nil`. `Action::Result` ganha `secret`, preenchido pelo `Runner` só em sucesso.
  - Com `result.secret` presente, `ActionsController#create` não redireciona: renderiza `actions/secret.html.erb` (200) com `response.headers["Cache-Control"] = "no-store"`. A página mostra um `<input readonly>` com o valor, o botão "Copiar" (em `app/assets/lucid_backoffice.js`, sem `<a href>` para o valor), o aviso e um link para "continuar" (o `redirect_url` do resultado ou o registro/lista).
  - O valor nunca vai para `flash`, `session`, `Activity` (o evento grava só nome, motivo e outcome) nem para os parâmetros logados. `config.filter_parameters` não é preciso, porque o valor não é parâmetro, e um teste garante que ele não aparece no log da requisição.
  - Com `secret` devolvendo `nil` ou vazio, o fluxo é o de hoje (redirect + notice).
  - O model sai de `tabela.classify.safe_constantize`. Sem model ActiveRecord, levanta `ConfigurationConflict` no boot.
  - Erros de validação (`ActiveRecord::RecordInvalid`, `RecordNotDestroyed`) viram `result` de falha com `errors.full_messages.to_sentence`.
- **Alvo de coleção:** `Action.on(:users, collection: true)` e `Action.collection?`. `ActionsController#find_record` devolve `nil` para ação de coleção. A lista renderiza as Ações de coleção no cabeçalho (a primeira é o botão primário), e o registro, as de registro.
- **Campo travado:**
  - `Action#initial_values` e o form recebem `revealed:`.
  - Um campo com o nome de uma coluna do alvo cuja categoria não é `public` nem está revelada vira `Action::Field::LOCKED`, sentinela que o form desenha como `<input disabled value="•••••">` com cadeado e o aviso, sem `name`, então nunca é enviado.
  - Na execução (`Runner`), um valor recebido para campo travado é descartado. O valor atual do registro é lido no servidor e passado ao `perform` e ao Command, para que nada vire `nil`.
  - Em ação de coleção, que não tem registro, nada trava.
  - A prévia continua mascarada como hoje.
- **Telas criadas ou editadas:**
  - `/backoffice/data/:table` e `/backoffice/tenants/:tenant_id/data/:table` (busca, filtros, ordenação, "Novo registro");
  - `/backoffice/data/:table/:id` e `/backoffice/tenants/:tenant_id/data/:table/:id` (links, Relacionados, Editar, Excluir);
  - `/backoffice/actions/:action_key/new` (campos travados, botões de opção de envio);
  - `POST /backoffice/actions/:action_key` (página de segredo de exibição única).
  - `staging: none` nos dois repos.
- **Testes:** o tester escreve os testes vermelhos de cada PR a partir dos cenários. A suíte de segurança ganha a rota não-GET `POST .../data/:table/query` e um teste de captura de SQL: nenhuma coluna oculta e nenhuma coluna mascarada não revelada no `WHERE` ou no `ORDER BY`.

## PR 1 — Campos travados nas Ações (branch: `feat/record-management-1`, base: `main` com a Spec A mergeada)

**Entrega:** a sentinela `LOCKED`. `initial_values(revealed:)` não devolve valor de coluna mascarada. O form desenha o campo travado. O `Runner` descarta o valor enviado para campo travado e injeta o valor atual lido no servidor. O controller passa `Reveal.categories_for`.
**Arquivos:** Modify `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/field.rb`, `lib/lucid/backoffice/action/runner.rb`, `app/controllers/lucid/backoffice/actions_controller.rb`, `app/views/lucid/backoffice/actions/_field.html.erb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml` (chave `locked_field`). Test `test/lucid/backoffice/action/field_test.rb`, `test/lucid/backoffice/action/runner_test.rb`, `test/integration/editable_test.rb`, `test/integration/actions_test.rb`.
**Pronto para prod:** fecha um vazamento. Ações sem campos mascarados não mudam.
**Valida:** `bundle exec rake test`

## PR 2 — Consulta: filtro, busca e ordenação por colunas utilizáveis (branch: `feat/record-management-2`, base: `feat/record-management-1`)

**Entrega:** `Records::Query` (`filters`, `search`, `sort`, `dir`, `usable?`, `ignored`) e `Records.list(query:, revealed:)`, com o SQL descrito acima. `Resource.search` aceita coluna não oculta. Sem UI ainda: o `index` passa uma `Query` montada só de `filter[...]` com as regras novas.
**Arquivos:** Create `lib/lucid/backoffice/records/query.rb`. Modify `lib/lucid/backoffice/records.rb`, `lib/lucid/backoffice/resource.rb`, `app/controllers/lucid/backoffice/records_controller.rb`. Test `test/lucid/backoffice/records_test.rb`, `test/lucid/backoffice/resource_test.rb`.
**Pronto para prod:** os filtros por `id` e `*_id` continuam iguais. Colunas públicas passam a valer na URL, e nada mascarado é aplicado sem revelação.
**Valida:** `bundle exec rake test`

## PR 3 — Barra de consulta na listagem e critério no servidor (branch: `feat/record-management-3`, base: `feat/record-management-2`)

**Entrega:**
- Barra acima da tabela: campo de busca, chips dos filtros ativos (com ✕) e "+ Filtro" em `<details>` (select de colunas utilizáveis e um valor).
- Cabeçalhos ordenáveis.
- `POST data/:table/query` e `POST tenants/:tenant_id/data/:table/query` gravando na sessão e redirecionando com `q`.
- Aviso de critério ignorado.
- `PanelActivity.browse` com `criteria: [nomes de coluna]`.
**Arquivos:** Create `app/views/lucid/backoffice/ui/_query_bar.html.erb`. Modify `config/routes.rb`, `app/controllers/lucid/backoffice/records_controller.rb`, `app/views/lucid/backoffice/records/index.html.erb`, `app/views/lucid/backoffice/ui/_table.html.erb`, `lib/lucid/backoffice/panel_activity.rb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml`. Test `test/integration/data_test.rb`, `test/integration/access_test.rb`, `test/lucid/backoffice/panel_activity_test.rb`.
**Pronto para prod:** a consulta é só leitura. A rota nova tem CSRF e entra na lista de rotas não-GET.
**Valida:** `bundle exec rake test`

## PR 4 — Links de chave estrangeira e Relacionados (branch: `feat/record-management-4`, base: `feat/record-management-3`)

**Entrega:**
- `Catalog.references(schema, table)` (ida) e `Catalog.referenced_by(schema, table)` (volta), na ordem de resolução descrita acima.
- `Records::Cell` ganha `link` (tabela e id) para coluna de chave estrangeira, renderizado em `ui/_value` no contexto atual.
- Card "Relacionados" no registro, com contagens.
**Arquivos:** Create `app/views/lucid/backoffice/ui/_related.html.erb`. Modify `lib/lucid/backoffice/catalog.rb`, `lib/lucid/backoffice/records.rb`, `app/controllers/lucid/backoffice/records_controller.rb`, `app/views/lucid/backoffice/ui/_value.html.erb`, `app/views/lucid/backoffice/records/show.html.erb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml`. Test `test/lucid/backoffice/catalog_test.rb`, `test/lucid/backoffice/records_test.rb`, `test/integration/data_test.rb`.
**Pronto para prod:** só leitura, aditivo.
**Valida:** `bundle exec rake test`

## PR 5 — `creatable`, `destroyable`, alvo de coleção e permissões de registro (branch: `feat/record-management-5`, base: `feat/record-management-4`)

**Entrega:**
- `Action.on(table, collection: true)`.
- `Resource.creatable` e `Resource.destroyable`.
- `editable` passa a usar `:update_record`.
- Redirecionamentos pós-execução: criar vai para o registro criado, excluir vai para a lista.
- Erros de validação viram falha legível.
- Ações de coleção no cabeçalho da lista.
**Arquivos:** Modify `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/runner.rb`, `lib/lucid/backoffice/resource.rb`, `app/controllers/lucid/backoffice/actions_controller.rb`, `app/views/lucid/backoffice/ui/_actions.html.erb`, `app/views/lucid/backoffice/records/index.html.erb`, `config/locales/pt-BR.yml`, `config/locales/en.yml` (chaves `new_record`, `destroy_record`, `edit`). Test `test/lucid/backoffice/resource_test.rb`, `test/lucid/backoffice/action/dsl_test.rb`, `test/integration/editable_test.rb`, `test/integration/actions_test.rb`.
**Pronto para prod:** nenhuma tabela ganha escrita sem declarar. Quem já usa `editable` precisa conceder `:update_record` (quebra anotada no `CHANGELOG`).
**Valida:** `bundle exec rake test`

## PR 6 — Bloco de configuração no Resource, opções de envio e e-mail disponível (branch: `feat/record-management-6`, base: `feat/record-management-5`)

**Entrega:**
- Bloco opcional em `creatable`, `editable` e `destroyable` (`class_eval` depois dos defaults).
- `Action.submit`, `Action.submits`, `#available_submits`, `#submitted`; `Runner` com `submit:`; botões na etapa final.
- `config.email_available` + `Lucid::Backoffice::Mail.available?` + `Action#email_available?`.

**Arquivos:** Create `lib/lucid/backoffice/mail.rb`. Modify `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/runner.rb`, `lib/lucid/backoffice/resource.rb`, `lib/lucid/backoffice/configuration.rb`, `app/controllers/lucid/backoffice/actions_controller.rb`, `app/views/lucid/backoffice/actions/new.html.erb`. Test `test/lucid/backoffice/mail_test.rb`, `test/lucid/backoffice/action/dsl_test.rb`, `test/lucid/backoffice/action/runner_test.rb`, `test/lucid/backoffice/resource_test.rb`, `test/integration/actions_test.rb`.
**Pronto para prod:** aditivo. Ação sem `submit` mostra o mesmo "Executar", e Resource sem bloco gera a mesma Action do PR 5.
**Valida:** `bundle exec rake test`

## PR 7 — Segredo de exibição única (branch: `feat/record-management-7`, base: `feat/record-management-6`)

**Entrega:** `Action.secret`, `#secret_for`, `Action::Result#secret`, renderização de `actions/secret.html.erb` (200, `no-store`, `<input readonly>`, "Copiar", aviso, "Continuar") e chaves i18n `secret_title`, `secret_warning`, `copy`, `copied`, `continue`.
**Arquivos:** Create `app/views/lucid/backoffice/actions/secret.html.erb`. Modify `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/runner.rb`, `app/controllers/lucid/backoffice/actions_controller.rb`, `app/assets/lucid_backoffice.js`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml`. Test `test/lucid/backoffice/action/runner_test.rb`, `test/integration/secret_test.rb` (HTML sem `<a href>` do valor, `Cache-Control: no-store`, valor ausente de flash, session, `Activity::Event` e log capturado; reload não mostra de novo; `secret` nil redireciona).
**Pronto para prod:** aditivo. Ação sem `secret` redireciona como antes.
**Valida:** `bundle exec rake test`

## PR 8 — Release 0.4.0 e documentação (branch: `feat/record-management-8`, base: `feat/record-management-7`)

**Entrega:**
- `VERSION = "0.4.0"`.
- `CHANGELOG` `## 0.4.0`, com a seção **Breaking**: `editable` exige `:update_record`; `search` aceita coluna não pública; `Records.list` recebe `query:`.
- Docs atualizadas.
- Nota no ADR 0004 do luneta apontando para o ADR 0001 da gem.
- Tag `v0.4.0` após o merge.
**Arquivos:** Modify `lib/lucid/backoffice/version.rb`, `CHANGELOG.md`, `docs/resources.md`, `docs/actions.md`, `docs/security.md`, `docs/masking-and-reveals.md`, `docs/configuration.md` (`email_available`), `README.md`. Luneta: `docs/adr/0004-own-sysadmin-panel-masked-by-default.md` (linha "Narrowed by lucid-backoffice ADR 0001: revealed columns are searchable"), num commit próprio no repo do luneta, dentro do PR 9.
**Pronto para prod:** só versão e docs.
**Valida:** `bundle exec rake test && git tag --list v0.4.0`

## PR 9 — Luneta: novo usuário, link de definição de senha e classrooms (repo luneta, branch: `feat/backoffice-record-actions`, base: `main` com o PR 8 da Spec A mergeado)

**Entrega:**
- Gem em `tag: 'v0.4.0'`.
- **`users`** (contexto de escola), tudo configurado no Resource:
  - `creatable :name, :email, :role, with: User::Invite do ... end`, com o bloco do exemplo em "Ação de registro": label "Novo usuário", `role` como select de `User.role.values` com default `owner`, `submit :email` (só com `email_available?`), `submit :link` e `secret { |result| result[:set_password_url] }`.
  - `editable :name, :email, :role`, no padrão sem `with:`, para mostrar o campo travado: `email` é `contact`.
- **`User::GenerateSetPasswordLink`** (Command novo, `attributes :user`):
  - gera `raw, enc = Devise.token_generator.generate(User, :reset_password_token)` e grava `reset_password_token: enc` e `reset_password_sent_at: Time.current`, o que invalida o link anterior;
  - devolve `success(resource: user, set_password_url:)` com `edit_user_password_url(reset_password_token: raw)` no host da escola atual (`Lucid::Tenancy::Hosts.url_options_for(Lucid::Tenancy.current)`, `https` fora de `Rails.env.local?`). A validade é o `reset_password_within` do Devise (6 horas).
- **`User::Invite`** (Command novo, `attributes :name, :email, :role, :submit`):
  - cria o `User` com `password: Devise.friendly_token(32)`; falha de validação vira `failure(:invalid, errors: user.errors.full_messages)` e nada é gravado;
  - com `submit` `link`, chama `User::GenerateSetPasswordLink` no corpo e devolve `success(resource: user, set_password_url:)`;
  - com `submit` `email`, devolve `success(resource: user)` e envia em `after_commit` via `User::SendPasswordReset.call(user:)`. Uma exceção ali é capturada no hook e enviada a `Rails.error.report` (Sentry), sem desfazer a criação.
- **`Actions::GenerateSetPasswordLink`** (`on :users`, registro, label "Gerar link de definição de senha", `perform with: User::GenerateSetPasswordLink`, `secret { |result| result[:set_password_url] }`). Não é CRUD, por isso é uma Action própria, como `SendPasswordReset`.
- **`classrooms`**, exemplo do padrão sem Command: Resource novo `Resources::Classrooms` com `creatable :grade_id, :shift_id`, `editable :shift_id` e `destroyable`. A exclusão remove a turma (`Classroom` não tem dependentes; o `has_many :enrollments` que ela declarava apontava para uma coluna inexistente e foi removido). A recusa pelo model é coberta na gem com `gadgets`/`parts`.
- `SysadminAbility` sem mudança: o superadmin já tem tudo, e o `support` não recebe `create_record`, `update_record`, `destroy_record` nem `run_action`. Um teste garante isso.
- `config/initializers/lucid_backoffice.rb` sem mudança: o default de `email_available` cobre o luneta (Resend via `:smtp` com `smtp.resend.com` em staging/production, `SMTP_HOST` em development, e `localhost` quando falta a chave).
**Arquivos:**
- Modify `modules/core/code/Gemfile`, `modules/core/code/Gemfile.lock`, `modules/core/code/app/backoffice/resources/users.rb`.
- Create `modules/core/code/app/backoffice/resources/classrooms.rb`, `modules/core/code/app/backoffice/actions/generate_set_password_link.rb`, `modules/core/code/app/core/cases/user/invite.rb`, `modules/core/code/app/core/cases/user/generate_set_password_link.rb`.
- Test `modules/core/code/test/core/cases/user/invite_test.rb` (link x e-mail, e-mail duplicado, falha no envio mantém o usuário), `modules/core/code/test/core/cases/user/generate_set_password_link_test.rb` (host da escola, token anterior invalidado, token funciona em `User.reset_password_by_token`), `modules/core/code/test/backoffice/resources/record_actions_test.rb` (botões com e sem e-mail disponível, segredo exibido uma vez, superadmin vê, support não), `modules/core/code/test/backoffice/actions/generate_set_password_link_test.rb`.
- Docs `docs/guides/sysadmin.md` e `docs/adr/0004-own-sysadmin-panel-masked-by-default.md`.
**Pronto para prod:** depende só da tag `v0.4.0`. `Resources::Organizations` já usa `editable ... with: Organization::Update` e passa a ter os campos de documentos travados até revelar.
**Valida:** `make core.test ARGS="test/core/cases/user/invite_test.rb test/core/cases/user/generate_set_password_link_test.rb test/backoffice/resources/record_actions_test.rb test/backoffice/actions/generate_set_password_link_test.rb"` e depois `make core.test`

## SEQUENCE
1. #<pr1> — Campos travados nas Ações
2. #<pr2> — Consulta: filtro, busca e ordenação por colunas utilizáveis
3. #<pr3> — Barra de consulta na listagem e critério no servidor
4. #<pr4> — Links de chave estrangeira e Relacionados
5. #<pr5> — creatable, destroyable, alvo de coleção e permissões
6. #<pr6> — Bloco no Resource, opções de envio e e-mail disponível
7. #<pr7> — Segredo de exibição única
8. #<pr8> — Release 0.4.0 e documentação
9. #<pr9> — Luneta: novo usuário, link de definição de senha e classrooms (após a tag v0.4.0)
Merge in this order: #<pr1> #<pr2> #<pr3> #<pr4> #<pr5> #<pr6> #<pr7> #<pr8> #<pr9>

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (`bundle exec rake test` na gem; `make core.test` no luneta)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (`docs/resources.md`, `docs/actions.md`, `docs/configuration.md`, `docs/security.md`, `docs/masking-and-reveals.md`, `README.md`, `CHANGELOG.md`; luneta `docs/guides/sysadmin.md` e nota no ADR 0004)
- [ ] Staging: `staging: none` nos dois repos — passo pulado e reportado
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (PR 9 declara as tabelas no luneta; nenhum código temporário na gem)
- [ ] Cenário "buscar por coluna pública": teste de integração com `filter[role]` na URL
- [ ] Cenário "coluna mascarada não é filtrável sem revelação": teste de `Records::Query#usable?` e de integração (fora do select, critério ignorado com aviso)
- [ ] Cenário "coluna revelada fica pesquisável": teste de integração do `POST .../query` → redirect com `q`, URL sem o texto buscado, evento `browse` com nomes de coluna e sem o valor
- [ ] Cenário "revelação acaba com o filtro aplicado": teste com o Reveal revogado e o mesmo `q`
- [ ] Cenário "coluna oculta nunca é critério": teste de captura de SQL (`ActiveSupport::Notifications` `sql.active_record`) sem a coluna oculta nem a mascarada não revelada em `WHERE`/`ORDER BY`
- [ ] Cenário "ordenar por coluna visível": teste de integração da ordem e da ausência de link nas mascaradas
- [ ] Cenário "link de chave estrangeira": teste de `Catalog.references` com FK real no banco de teste e de DOM
- [ ] Cenário "Relacionados": teste de `Catalog.referenced_by` e da contagem e do link filtrado
- [ ] Cenários de criar (sucesso, validação, tabela não declarada, sem permissão): testes de `Resource.creatable` e de integração (registro criado, evento com motivo, redirect; 404; 403)
- [ ] Cenários de campo travado (travado, destrava, enviado à força, Command recebe o valor atual): testes de `initial_values`, do `Runner` e de integração (HTML sem o valor mascarado)
- [ ] Cenários de excluir (sucesso e recusa do model): testes de `Resource.destroyable` com `danger :high` e falha legível
- [ ] Bloco de configuração: teste de `Resource.creatable`/`editable`/`destroyable` com bloco sobrescrevendo `label` e `field` e adicionando `submit` e `secret` (`resource_test.rb`)
- [ ] Cenários "opções de envio viram botões", "opção indisponível some" e "Ação sem submit declarado": testes de `Action.submit`/`available_submits` (`dsl_test.rb`), do `Runner` recusando `submit` fora da lista (`runner_test.rb`) e de DOM da etapa final (`actions_test.rb`)
- [ ] Cenário "e-mail disponível lido do Rails": `mail_test.rb` cobre `:smtp` com address, sem address, `localhost`, `perform_deliveries false`, `:test`/`:file`/método custom e o override por `config.email_available`
- [ ] Cenários "segredo de exibição única" e "segredo vazio segue o fluxo normal": `secret_test.rb` (200, `no-store`, `<input readonly>` com o valor, nenhum `<a href>` com o valor, valor ausente de flash, session, `Activity::Event` e log; reload sem o valor; `nil` redireciona)
- [ ] Cenários "luneta, novo usuário por e-mail" e "por link": `invite_test.rb` (e-mail enviado depois do commit com host da escola; link no host da escola e nenhum e-mail) e `record_actions_test.rb` (redirect ao registro no e-mail, página de segredo no link)
- [ ] Cenário "luneta sem e-mail configurado": `record_actions_test.rb` com `email_available` falso mostra só "Criar e copiar link"
- [ ] Cenário "luneta, e-mail já em uso": `invite_test.rb` (nada criado, falha `:invalid` com a mensagem do User) e `record_actions_test.rb` (form volta preenchido)
- [ ] Cenário "luneta, falha no envio do e-mail": `invite_test.rb` com `User::SendPasswordReset` levantando, o usuário persiste e `Rails.error.report` é chamado
- [ ] Cenário "luneta, gerar link de definição de senha": `generate_set_password_link_test.rb` (case e action), com o token anterior inválido e o novo aceito por `User.reset_password_by_token`
- [ ] Cenário "exemplos no luneta": `make core.test` verde com os testes de `User::Invite` e de `record_actions_test.rb` (superadmin vê as ações, support não vê nenhuma, nem "Gerar link de definição de senha")
- [ ] Tag `v0.4.0` publicada no remoto da gem
- [ ] Banner `FINISHED` impresso como última saída (`br4zz4:finish`, Step 7), só com todos os itens acima marcados

## documentation

- `docs/adr/0001-search-revealed-columns-server-side.md` (criado nesta entrevista).
- `docs/CONTEXT.md`: coluna visível, coluna oculta, campo travado, ação de registro (criado nesta entrevista).
- `docs/resources.md`: `search` (coluna não oculta), `filter`, `association`, `creatable`, `editable` (`:update_record`), `destroyable`.
- `docs/actions.md`: alvo de coleção, campos travados, permissões de registro, `submit`, `secret`, `email_available?` e o bloco de configuração em `creatable`/`editable`/`destroyable`.
- `docs/configuration.md`: `config.email_available` e o default lido do ActionMailer.
- `docs/CONTEXT.md`: collection action, submit option, one-time secret, email available (criado nesta revisão).
- Luneta `docs/CONTEXT.md`: Link de definição de senha (criado nesta revisão).
- `docs/security.md`: critérios no servidor, rota `query`, regra de coluna utilizável.
- `docs/masking-and-reveals.md`: o que a revelação libera (leitura, busca e edição).
- `CHANGELOG.md`: `0.4.0` com Breaking.
- Luneta: `docs/guides/sysadmin.md` (novo usuário por e-mail ou link, gerar link de definição de senha, turmas) e nota no ADR 0004.
