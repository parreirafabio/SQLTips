

CREATE PROCEDURE Usp_MoveBancoDeDadosParaOutroDisco
@NomeBancoDeDados AS NVARCHAR(150),
@CaminhoNovoBancoArquivoData AS NVARCHAR(200),
@CaminhoNovoBancoArquivoLog AS NVARCHAR(200)
AS
BEGIN
	DECLARE @CaminhoTable AS TABLE( Id TINYINT, NomeArquivo  VARCHAR(50), CaminhoArquivo  VARCHAR(500))
	DECLARE @CaminhoLogBancoAtual AS NVARCHAR(500)
	DECLARE @CaminhoDadosBancoAtual AS NVARCHAR(500)
	DECLARE @NomeArquivoLogBancoAtual AS NVARCHAR(500)
	DECLARE @NomeArquivoDadosBancoAtual AS NVARCHAR(500)
	DECLARE @NomeArquivoLogBancoAtualOrignal AS NVARCHAR(500)
	DECLARE @NomeArquivoDadosBancoAtualOriginal AS NVARCHAR(500)
	DECLARE @Cmd NVARCHAR(4000)
	DECLARE @ComandoCopiarArquivo AS NVARCHAR(500)
	DECLARE @ComandoRenomearArquivo AS NVARCHAR(500)
	DECLARE @NomeArquivoDadosFisico AS NVARCHAR(500)
	DECLARE @NomeArquivoLogFisico AS NVARCHAR(500)	
	/*
		USE ESSA CONFIGURAÇÃO PARA LIBERAR O POWER SHEL OU CMD
		USE master;  
		GO  
		EXEC sp_configure 
				'show advanced option', 
				'1';  
		RECONFIGURE WITH OVERRIDE;

		EXEC sp_configure 'xp_cmdshell', 1;  
		GO  
		RECONFIGURE;

		
	*/

	BEGIN
		BEGIN--LIBERAR SHELL SERVIDOR
			EXEC sp_configure 
				'show advanced option', 
				'1';  
			RECONFIGURE WITH OVERRIDE;
			--LIBERA O BANCO DE DADOS PARA EXECUTAR O SHEL
		    EXEC sp_configure 'xp_cmdshell', 1;  
		
			RECONFIGURE;
		END

		BEGIN TRY
			BEGIN--INCLUIR CAMINHO ATUAL DO BANCO DE DADOS
				INSERT INTO
					@CaminhoTable
				SELECT 
					 ROW_NUMBER() OVER (ORDER BY name) AS Id,
					name, 
					physical_name 
				FROM 
					sys.master_files  
				WHERE 
					database_id = DB_ID(@NomeBancoDeDados); 	
			END

			BEGIN-- PREENCHENDO VALORES DAS VARIÁVEIS
				SET @CaminhoDadosBancoAtual = (SELECT TOP 1 CaminhoArquivo FROM @CaminhoTable WHERE CaminhoArquivo LIKE '%.mdf')
				SET @CaminhoLogBancoAtual = (SELECT TOP 1 CaminhoArquivo FROM @CaminhoTable WHERE CaminhoArquivo LIKE '%.ldf')
				SET @NomeArquivoDadosBancoAtual = (SELECT TOP 1 NomeArquivo FROM @CaminhoTable WHERE CaminhoArquivo LIKE '%.mdf')
				SET @NomeArquivoLogBancoAtual = (SELECT TOP 1 NomeArquivo FROM @CaminhoTable WHERE CaminhoArquivo LIKE '%.ldf')
				SET @NomeArquivoDadosBancoAtualOriginal = (SELECT TOP 1 NomeArquivo FROM @CaminhoTable WHERE CaminhoArquivo LIKE '%.mdf')
				SET @NomeArquivoLogBancoAtualOrignal = (SELECT TOP 1 NomeArquivo FROM @CaminhoTable WHERE CaminhoArquivo LIKE '%.ldf')
			END

			BEGIN--ALTERA BANCO OFFLINE 

				BEGIN-- MATA TODAS CONEÇÕES ATIVASDO BANCO DE DADOS
					DECLARE @kill varchar(8000) = '';  
					SELECT @kill = @kill + 'kill ' + CONVERT(varchar(5), session_id) + ';'  
					FROM sys.dm_exec_sessions
					WHERE database_id  = db_id(@NomeBancoDeDados)

					EXEC(@kill);
				END

				SET @Cmd='ALTER DATABASE '+@NomeBancoDeDados+' SET OFFLINE;'
				EXEC sp_executeSQL @cmd	
				BEGIN--COPIA O ARQUIVO DE DADOS
					--COPIA
					SET @ComandoCopiarArquivo = 'copy "' + @CaminhoDadosBancoAtual  + '"  "' +  @CaminhoNovoBancoArquivoData +'"'
					EXEC xp_cmdshell @ComandoCopiarArquivo		
					--RENOMEIA
					BEGIN--VERICA SE O NOME DO ARQUIVO É DIFERENTE DO NOME DO ARQUIVO LOGIGO
						SELECT @NomeArquivoDadosFisico = REVERSE(SUBSTRING(REVERSE(@CaminhoDadosBancoAtual),0,CHARINDEX('\',REVERSE(@CaminhoDadosBancoAtual),0)))
						IF(REPLACE(@NomeArquivoDadosFisico,'.mdf','') <> @NomeArquivoDadosBancoAtual)--NOME É DIFERENTE
						BEGIN
							SET @ComandoRenomearArquivo = 'REN '+ @CaminhoNovoBancoArquivoData  + '\' + @NomeArquivoDadosFisico + N' ' + @NomeBancoDeDados + N'.mdf' 
							PRINT @ComandoRenomearArquivo
							EXEC xp_cmdshell @ComandoRenomearArquivo		
							SET @NomeArquivoDadosBancoAtual = @NomeBancoDeDados
						END
					END		
				END
				BEGIN--COPIA O ARQUIVO DE LOG
					SET @ComandoCopiarArquivo = 'copy "' + @CaminhoLogBancoAtual  + '"  "' +  @CaminhoNovoBancoArquivoLog +'"'
					EXEC xp_cmdshell @ComandoCopiarArquivo	
					--RENOMEIA
					BEGIN--VERICA SE O NOME DO ARQUIVO É DIFERENTE DO NOME DO ARQUIVO LOGIGO
						SELECT @NomeArquivoLogFisico = REVERSE(SUBSTRING(REVERSE(@CaminhoLogBancoAtual),0,CHARINDEX('\',REVERSE(@CaminhoLogBancoAtual),0)))
						IF(REPLACE(@NomeArquivoLogFisico,'.ldf','') <> @NomeArquivoLogBancoAtual)--NOME É DIFERENTE
						BEGIN
							SET @ComandoRenomearArquivo = 'REN '+ @CaminhoNovoBancoArquivoLog  + '\' + @NomeArquivoLogFisico + N' ' + @NomeBancoDeDados + N'_log.ldf'  
							PRINT @ComandoRenomearArquivo
							EXEC xp_cmdshell @ComandoRenomearArquivo	
							SET @NomeArquivoLogBancoAtual =  @NomeBancoDeDados + N'_log'
						END
					END		
				END	
			END

			BEGIN--ALTERA O CAMINHO DO BANCO DE DADOS PARA O NOVO CAMINHO
				SET @Cmd = N'ALTER DATABASE ' + @NomeBancoDeDados + N' MODIFY FILE ( NAME = ' + @NomeArquivoDadosBancoAtualOriginal + N', FILENAME = ''' + @CaminhoNovoBancoArquivoData +'\' + @NomeArquivoDadosBancoAtual + N'.mdf'')'
				PRINT @Cmd
				EXEC sp_executeSQL @cmd	
				SET @Cmd = N'ALTER DATABASE ' + @NomeBancoDeDados + N' MODIFY FILE ( NAME = ' + @NomeArquivoLogBancoAtualOrignal + N', FILENAME = '''  + @CaminhoNovoBancoArquivoLog +'\' + @NomeArquivoLogBancoAtual + N'.ldf'')'
				PRINT @Cmd
				EXEC sp_executeSQL @cmd	
			END

			BEGIN--TORNA BANCO ONLINE
				SET @Cmd='ALTER DATABASE '+@NomeBancoDeDados+' SET ONLINE;'
				EXEC sp_executeSQL @cmd	
			END

			BEGIN--DELISGAR SHELL BANCO DE DADOS
				 EXEC sp_configure 'xp_cmdshell', 0;  
			END
		END TRY
		BEGIN CATCH
		    BEGIN--DELISGAR SHELL BANCO DE DADOS
				 EXEC sp_configure 'xp_cmdshell', 0;  
			END
			--VERIFICA SE O BANCO DE DADOS ESTÁ ONLINE OU NÃO PARA VOLTAR O MESMO AO ESTADO ANTERIOR
			IF EXISTS (SELECT name FROM master.sys.databases
			WHERE name = @NomeBancoDeDados AND state_desc = 'ONLINE')
			BEGIN
					SET @Cmd='ALTER DATABASE '+@NomeBancoDeDados+' SET OFFLINE;'
					EXEC sp_executeSQL @cmd	
			END
			BEGIN--VOLTA OS DADOS ORIGINAIS DO BANCO
				SET @Cmd = N'ALTER DATABASE ' + @NomeBancoDeDados + N' MODIFY FILE ( NAME = ' + @NomeArquivoDadosBancoAtualOriginal + N', FILENAME = ''' + @CaminhoDadosBancoAtual + N''')'
				PRINT @Cmd
				EXEC sp_executeSQL @cmd	
				SET @Cmd = N'ALTER DATABASE ' + @NomeBancoDeDados + N' MODIFY FILE ( NAME = ' + @NomeArquivoLogBancoAtualOrignal + N', FILENAME = '''  + @CaminhoLogBancoAtual + N''')'
				PRINT @Cmd
				EXEC sp_executeSQL @cmd	
			END
			BEGIN--TORNA BANCO ONLINE
				SET @Cmd='ALTER DATABASE '+@NomeBancoDeDados+' SET ONLINE;'
				EXEC sp_executeSQL @cmd	
			END
		END CATCH
	END
END
