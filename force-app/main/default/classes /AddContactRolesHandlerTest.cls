@IsTest
public class AddContactRolesHandlerTest {

    @TestSetup
    static void setupTestData() {
        final List<Account> accounts = new List<Account>{
            new Account(Name = 'Account A'),
            new Account(Name = 'Account B')
        };
        insert accounts;

        final List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'John', LastName = 'Doe', AccountId = accounts[0].Id),
            new Contact(FirstName = 'Jane', LastName = 'Smith', AccountId = accounts[0].Id),
            new Contact(FirstName = 'Bob', LastName = 'Wilson', AccountId = accounts[1].Id)
        };
        insert contacts;
    }

    @IsTest
    static void handleAfterInsert_whenOpportunityIsClosedWon_createsContactRoles() {
        // Arrange
        final Account account = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        final List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'Closed Won Opportunity',
                StageName = 'Closed Won',
                CloseDate = System.today(),
                AccountId = account.Id
            )
        };
            insert opportunities;

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterInsert(opportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id
            FROM OpportunityContactRole 
            WHERE OpportunityId = :opportunities[0].Id
        ];
        Assert.areEqual(2, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');
    }

    @IsTest
    static void handleAfterInsert_opportunityIsNotClosedWon_doesNotCreateContactRoles() {
        // Arrange
        final Account account = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        final List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'Prospecting Opportunity',
                StageName = 'Prospecting',
                CloseDate = System.today(),
                AccountId = account.Id
            )
        };
             insert opportunities;

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterInsert(opportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id FROM OpportunityContactRole 
            WHERE OpportunityId = :opportunities[0].Id
        ];
        Assert.areEqual(0, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');
    }

    @IsTest
    static void handleAfterInsert_opportunityWithoutAccount_doesNotCreateContactRoles() {
        // Arrange
        final List<Opportunity> opportunities = new List<Opportunity>{
            new Opportunity(
                Name = 'No Account Opportunity',
                StageName = 'Closed Won',
                CloseDate = Date.newInstance(2026, 12, 31),
                AccountId = null
            )
        };

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterInsert(opportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id FROM OpportunityContactRole
        ];
        Assert.areEqual(0, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');
    }

    @IsTest
    static void handleAfterUpdate_StageChangedToClosedWon_CreatesContactRoles() {
        // Arrange
        final Account account = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        final Opportunity opportunity = new Opportunity(
            Name = 'Stage Change Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.newInstance(2026, 12, 31),
            AccountId = account.Id
        );
        insert opportunity;

        final Map<Id, Opportunity> existingOpportunities = new Map<Id, Opportunity>{
            opportunity.Id => new Opportunity(Id = opportunity.Id, StageName = 'Prospecting', AccountId = account.Id)
        };
        opportunity.StageName = 'Closed Won';
        final Map<Id, Opportunity> newOpportunityMap = new Map<Id, Opportunity>{ opportunity.Id => opportunity };

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterUpdate(newOpportunityMap, existingOpportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id FROM OpportunityContactRole 
            WHERE OpportunityId = :opportunity.Id
        ];
        Assert.areEqual(2, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');
    }

    @IsTest
    static void handleAfterUpdate_StageChangedFromClosedWon_DeletesContactRoles() {
        // Arrange
        final Account account = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        final Opportunity opportunity = new Opportunity(
            Name = 'Stage Reverse Opportunity',
            StageName = 'Closed Won',
            CloseDate = Date.newInstance(2026, 12, 31),
            AccountId = account.Id
        );
        insert opportunity;

        // Create initial contact roles
        AddContactRolesHandler.handleAfterInsert(new List<Opportunity>{ opportunity });

        final Map<Id, Opportunity> existingOpportunities = new Map<Id, Opportunity>{
            opportunity.Id => new Opportunity(Id = opportunity.Id, StageName = 'Closed Won', AccountId = account.Id)
        };
        opportunity.StageName = 'Prospecting';
        final Map<Id, Opportunity> newOpportunityMap = new Map<Id, Opportunity>{ opportunity.Id => opportunity };

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterUpdate(newOpportunityMap, existingOpportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id FROM OpportunityContactRole 
            WHERE OpportunityId = :opportunity.Id
        ];
        Assert.areEqual(0, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');
    }

    @IsTest
    static void handleAfterUpdate_AccountChangedOnClosedWon_UpdatesContactRoles() {
        // Arrange
        final List<Account> accounts = [SELECT Id FROM Account ORDER BY Name];
        final Account accountA = accounts[0]; // Account A has 2 contacts
        final Account accountB = accounts[1]; // Account B has 1 contact

        final Opportunity opportunity = new Opportunity(
            Name = 'Account Change Opportunity',
            StageName = 'Closed Won',
            CloseDate = System.today(),
            AccountId = accountA.Id
        );
        insert opportunity;

        // Create initial contact roles for Account A
        AddContactRolesHandler.handleAfterInsert(new List<Opportunity>{ opportunity });

        final Map<Id, Opportunity> existingOpportunities = new Map<Id, Opportunity>{
            opportunity.Id => new Opportunity(Id = opportunity.Id, StageName = 'Closed Won', AccountId = accountA.Id)
        };
        opportunity.AccountId = accountB.Id;
        final Map<Id, Opportunity> newOpportunityMap = new Map<Id, Opportunity>{ opportunity.Id => opportunity };

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterUpdate(newOpportunityMap, existingOpportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id, ContactId FROM OpportunityContactRole 
            WHERE OpportunityId = :opportunity.Id
        ];
        Assert.areEqual(1, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');

        final List<Contact> accountBContacts = [SELECT Id FROM Contact WHERE AccountId = :accountB.Id];
        Assert.areEqual(accountBContacts[0].Id, contactRoles[0].ContactId, 'Should be linked to Account B contact');
    }

    @IsTest
    static void handleAfterInsert_BulkScenario_HandlesMultipleOpportunities() {
        // Arrange
        final Account account = [SELECT Id FROM Account WHERE Name = 'Account A' LIMIT 1];
        final List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < 5; i++) {
            opportunities.add(new Opportunity(
                Name = 'Bulk Opportunity ' + i,
                StageName = 'Closed Won',
                CloseDate = System.today(),
                AccountId = account.Id
            ));
        }
        insert opportunities;

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterInsert(opportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id FROM OpportunityContactRole
        ];
        Assert.areEqual(10, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');
    }

    @IsTest
    static void handleAfterInsert_emptyList_handlesGracefully() {
        // Arrange
        final List<Opportunity> opportunities = new List<Opportunity>();

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterInsert(opportunities);
        Test.stopTest();

        // Assert
        final List<OpportunityContactRole> contactRoles = [
            SELECT Id FROM OpportunityContactRole
        ];
        Assert.areEqual(0, contactRoles.size(), 'Unexpected  no of opportunity contact roles created');
    }

    @IsTest
    static void handleAfterUpdate_emptyList_handlesGracefully() {
        // Arrange
        final Map<Id, Opportunity> newOpportunityMap = new Map<Id, Opportunity>();
        final Map<Id, Opportunity> existingOpportunities = new Map<Id, Opportunity>();

        // Act
        Test.startTest();
        AddContactRolesHandler.handleAfterUpdate(newOpportunityMap, existingOpportunities);
        Test.stopTest();

        // Assert
        Assert.isTrue(true, 'Unexpected  no of opportunity contact roles created');
    }
}
