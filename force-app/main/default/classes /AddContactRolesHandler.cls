public class AddContactRolesHandler {
    
    // Recursion prevention flag to avoid infinite trigger looping
    private static Boolean isProcessing = false;
    
    // Creates opportunityContactRoles for opportunities that are inserted as "Closed Won"
    public static void handleAfterInsert(final List<Opportunity> opportunityList) {
        // Prevent recursion if this handler is already processing
        if (isProcessing) {
            return;
        }
        isProcessing = true;
        
        try {
            final List<Opportunity> closedWonOpportunities = new List<Opportunity>();
        
            for (Opportunity opportunity : opportunityList) {
                if (opportunity.StageName == 'Closed Won' && opportunity.AccountId != null) {
                    closedWonOpportunities.add(opportunity);
                }
            }
            createContactRoles(closedWonOpportunities);
            
        } finally {
            // Always reset the processing flag
            isProcessing = false;
        }
    }
    
    // When stageName Updated to Closed Won
    // When accountId Changed for a closed Won Opportunity
    // When stageName Reversed from Closed Won
    public static void handleAfterUpdate(final Map<Id, Opportunity> newMap, final Map<Id, Opportunity> oldMap) {
        if (isProcessing) {
            return;
        }
        isProcessing = true;
        
        try {
            final List<Opportunity> newClosedWonOpps = new List<Opportunity>();
            final List<Opportunity> accountChangedOpps = new List<Opportunity>();
            final List<Opportunity> stageReversedOpps = new List<Opportunity>();
            
            for (Opportunity opp : newMap.values()) {
                final Opportunity oldOpp = oldMap.get(opp.Id);
                
                final Boolean nowClosedWon = (opp.StageName == 'Closed Won');
                final Boolean wasClosedWon = (oldOpp.StageName == 'Closed Won');
                final Boolean accountChanged = (opp.AccountId != oldOpp.AccountId);
                
                // If StageName of opportunity changed to Closed Won then add OCRs
                if (nowClosedWon && !wasClosedWon && opp.AccountId != null) {
                    newClosedWonOpps.add(opp);
                }
                
                // If accountId of opportunity changed while Closed Won then delete old OCRs and add new OCRs
                if (nowClosedWon && accountChanged) {
                    accountChangedOpps.add(opp);
                }
                
                // If Stage changed from Closed Won then delete OCRs
                if (!nowClosedWon && wasClosedWon) {
                    stageReversedOpps.add(opp);
                }
            }
            
            // Delete old OpportunityContactRoles - Deletion Comes first
            deleteContactRoles(accountChangedOpps);
            deleteContactRoles(stageReversedOpps);
            
            // Add new OpportunityContactRoles for Closed Won or changed Account
            createContactRoles(newClosedWonOpps);
            createContactRoles(accountChangedOpps);
        } finally {
            isProcessing = false;
        }
    }
    
    //Creates OpportunityContactRole records for all contacts associated with the opportunities' accounts  
    private static void createContactRoles(final List<Opportunity> opportunityList) {
        if (opportunityList == null || opportunityList.isEmpty()) {
            return;
        }
        
        final Set<Id> opportunityIds = new Set<Id>();
        final Set<Id> accountIds = new Set<Id>();
        
        for (Opportunity opportunity : opportunityList) {
            if (opportunity.AccountId != null && opportunity.Id != null) {
                opportunityIds.add(opportunity.Id);
                accountIds.add(opportunity.AccountId);
            }
        }
        
        if (accountIds.isEmpty()) {
            return;
        }
        
        // Get existing OCRs keys to prevent duplicate OCRs creation
        final Set<String> existingContactRoleKeys = getExistingContactRoleKeys(opportunityIds);
        if (existingContactRoleKeys == null) {
            return;
        }
        
        // Create map of accountIds to their contact Ids
        final Map<Id, Set<Id>> accountToContactsMap = buildAccountToContactsMap(accountIds);
        if (accountToContactsMap.isEmpty()) {
            return;
        }
        
        // Create opportunity contact role records to insert
        final List<OpportunityContactRole> contactRolesToInsert = new List<OpportunityContactRole>();
        for (Opportunity opportunity : opportunityList) {
            final Set<Id> contactIds = accountToContactsMap.get(opportunity.AccountId);
            if (contactIds != null && !contactIds.isEmpty()) {
                buildContactRoles(opportunity, contactIds, existingContactRoleKeys, contactRolesToInsert);
            }
        }
        
        // Insert contact roles 
        if (!contactRolesToInsert.isEmpty()) {
            insert contactRolesToInsert;
        }
    }
    
   // Deletes all OpportunityContactRole records
    private static void deleteContactRoles(final List<Opportunity> opportunityList) {
        if (opportunityList == null || opportunityList.isEmpty()) {
            return;
        }
        
        // Collect opportunity IDs to delete opportunity contact roles for
        final Set<Id> opportunityIdsToDelete = new Set<Id>();
        for (Opportunity opportunity : opportunityList) {
            if (opportunity.Id != null) {
                opportunityIdsToDelete.add(opportunity.Id);
            }
        }

        // Exit if no valid opportunity IDs found
        if (opportunityIdsToDelete.isEmpty()) {
            return;
        }

        try {
            // Query existing contact roles for these opportunities
            final List<OpportunityContactRole> contactRolesToDelete = [
                SELECT Id 
                FROM OpportunityContactRole 
                WHERE OpportunityId IN :opportunityIdsToDelete
            ];
            
            // Delete contact roles if any exist
            if (!contactRolesToDelete.isEmpty()) {
                delete contactRolesToDelete;
                System.debug('Successfully deleted ' + contactRolesToDelete.size() + ' OpportunityContactRole records');
            }
        } catch(Exception e) {
            System.debug('Error Message: '+ e);
        }
    }
    
  // Collect existing OpportunityContactRole check to avoid duplicates
    private static Set<String> getExistingContactRoleKeys(final Set<Id> opportunityIds) {
        final Set<String> existingContactRoleKeys = new Set<String>();
        
        try {
            // Query existing contact roles for these opportunities
            final List<OpportunityContactRole> existingContactRoles = [
                SELECT OpportunityId, ContactId 
                FROM OpportunityContactRole 
                WHERE OpportunityId IN :opportunityIds
                LIMIT 10000
            ];
            
            for (OpportunityContactRole existingRole : existingContactRoles) {
                final String compositeKey = String.valueOf(existingRole.OpportunityId) + '-' + String.valueOf(existingRole.ContactId);
                existingContactRoleKeys.add(compositeKey);
            }
            
            return existingContactRoleKeys;
            
        } catch(Exception e) {
            System.debug('Error Message: '+ e);
            return null;
        }
    }
   
    // Build map of AccountId to their Contact Ids
    private static void buildContactRoles(final Opportunity opportunity, final Set<Id> contactIds, 
                                         final Set<String> existingContactRoleKeys, 
                                         final List<OpportunityContactRole> contactRolesToInsert) {
        
        for (Id contactId : contactIds) {
            final String compositeKey = String.valueOf(opportunity.Id) + '-' + String.valueOf(contactId);
            
            // Only create if this key doesn't already exist
            if (!existingContactRoleKeys.contains(compositeKey)) {
                contactRolesToInsert.add(new OpportunityContactRole(
                    OpportunityId = opportunity.Id,
                    ContactId = contactId,
                    Role = 'Family Member',
                    IsPrimary = false
                ));
            }
        }
    }
    
    // Build map of AccountId to their Contact Ids
    private static Map<Id, Set<Id>> buildAccountToContactsMap(final Set<Id> accountIds) {
        final Map<Id, Set<Id>> accountIdWithContactIds = new Map<Id, Set<Id>>();
        
        try {
            final List<Contact> contactList = [
                SELECT Id, AccountId 
                FROM Contact 
                WHERE AccountId IN :accountIds
                LIMIT 10000
            ];
    
            for (Contact con : contactList) {
                final Set<Id> contactGroup = accountIdWithContactIds.get(con.AccountId);
                if (contactGroup == null) {
                    accountIdWithContactIds.put(con.AccountId, new Set<Id>{ con.Id });
                } else {
                    contactGroup.add(con.Id);
                }
            }
            
        } catch(Exception e) {
            System.debug('Error Message: ' + e);
        }
        
        return accountIdWithContactIds;
    }
}